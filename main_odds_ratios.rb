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
output_root = "odds_ratios_with_race"

# ======================  Step 1 : keep only follow ups  ======================

last_filename_root = Analyze.resave_with_prior_visit_counts( input_root )

last_filename_root = Analyze.resave_if( lambda {|item, i, s| 
   [item].type_office_followup.loc_south_pav.any? and ([item].status_completed.any? or [item].status_no_show.any?)
}, last_filename_root, "fu_sopa")

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

training_fraction = 0.9
training_features, test_features = Analyze.extract_training_and_test_features_from_file(last_filename_root, training_fraction )

# =============================================================================
# ========================   assembling into instances   ======================


stats = Analyze.train_odds_ratios( training_features )

puts stats

stats = stats.sort_by do |csv_row|
   k,v = csv_row[:feature_name].split("=")
   if v[0] == "<"
      "#{k}#{ "0" * 9 }"
   elsif v[0] == ">"
      "#{k}#{ "z" * 9 }"
   else
      "#{k}#{v.to_i.to_s.rjust(9, "0")}"
   end
end



headers = stats.first.keys
CSV.open("#{ output_root }_coefficients.csv", "wb") do |csv_out|
   csv_out << headers
   stats.each do |e|
      csv_out << headers.collect {|f| e[f] }
   end
end
puts "Done. Saved as #{ output_root }_coefficients.csv"
