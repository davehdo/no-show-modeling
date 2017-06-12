# this script analyzes EPIC data

# exported from business objects… (PROMIS)

# =====================   GETTING STARTED INSTRUCTIONS   ====================
# use jruby-9.1.2.0 rather than ruby
# rbenv local jruby-9.1.2.0
# which has equivalence of ruby 2.3.0

# first run gem install weka (but first ensure that jruby is chosen)

rec_ruby_v = "2.3.0"

puts "Warning: Running ruby #{ RUBY_VERSION }. (Recommend #{ rec_ruby_v })" unless rec_ruby_v ==  RUBY_VERSION

require "csv"
require "./filters.rb"
# require "./reports.rb"
require "./analyze.rb"

require 'weka' # requires jruby
# https://github.com/paulgoetze/weka-jruby/wiki


# =============================================================================
# ===============================  parameters  ================================
input_root = "neurology_provider_visits_with_payer_20170608"
output_root = "odds_ratios"

# ======================  Step 1 : keep only follow ups  ======================
last_filename_root = Analyze.resave_if( lambda {|item, i, s| [item]
   .type_office_followup.loc_south_pav.any?}, input_root, "fu_sopa")

# =========================  Step 2 : eliminate dup  ==========================
# amongst completed encounters, eliminate the duplicate encounters associated 
# with Botox and EMG so we don't overcount minutes of patients seen
last_filename_root = Analyze.resave_without_dup( last_filename_root, "dup")

# =======================  Step 3 : truncate for now  =========================
# Analyze.resave_sample( 2000, "#{ input_root}_fu_sopa_dup", "samp")
Analyze.output_characteristics( last_filename_root, 
   suffix: "characteristics", 
   censor: ["CSN", "Patient Name", "MRN"]
)

# =============================================================================
# Pecularities of the data
# - sometimes there is identical patient in a slot twice, one cancelled, 
#   and one completed
# - Botox and EMG can sometimes have duplicate, triplicate, or even 4x of
#   same patient, same timeslot, same visit type, same status (completed)
#   DOE,JOHN EMG (Completed 15) / DOE,JOHN EMG (Completed 15)


# =============================================================================
# ===========================   extract features   ============================

training_fraction = 0.8

valid_row_indexes = Array.new
n_read = 0
CSV.foreach( "#{last_filename_root}.csv", headers: true ) do |row|
  item = Hash[row]
  
  if [item].status_completed.any? or [item].status_no_show.any?
    valid_row_indexes << n_read
  end
  n_read += 1
end
puts "  There are #{ valid_row_indexes.size} valid rows in #{ last_filename_root }"

puts "Separating into training and test sets"
training_indexes = valid_row_indexes.sample( (valid_row_indexes.size * training_fraction).round)
test_indexes = valid_row_indexes - training_indexes
puts """  There should be #{training_indexes.size} training and 
#{test_indexes.size} test instances"""

puts "Extracting features for training and test sets"
training_features = Analyze.load_and_extract_features_from_encounters_file( last_filename_root, training_indexes )
test_features = Analyze.load_and_extract_features_from_encounters_file( last_filename_root, test_indexes )

puts """  Done. Extracted features for #{ training_features.size } training and
#{ test_features.size } test instances"""


# =============================================================================
# ========================   assembling into instances   ======================



puts "Creating instances prototype based on existing features"
puts "  Make sure these features are correct"


stats = Analyze.train_odds_ratios( training_features )

# puts stats

headers = stats.first.keys
CSV.open("#{ output_root }_coefficients.csv", "wb") do |csv_out|
   csv_out << headers
   stats.each do |e|
      csv_out << headers.collect {|f| e[f] }
   end
end

