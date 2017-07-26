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
output_root = "provider_type"

# =====================  Step 1 : Add calculated columns  =====================
last_filename_root = Analyze.resave_with_prior_visit_counts( input_root )

# ====================  Step 2 : Modify columns like dates  ===================


# =====================  Step 3 : Filter rows of interest  ====================
last_filename_root = Analyze.resave_if( lambda {|item, i, s| 
   [item].type_office_followup.loc_south_pav.any? and ([item].status_completed.any? or [item].status_no_show.any?)
}, last_filename_root, "fu_sopa")

# ======================  Step 4 : eliminate duplicates  ======================
# amongst completed encounters, eliminate the duplicate encounters associated 
# with Botox and EMG so we don't overcount minutes of patients seen
last_filename_root = Analyze.resave_without_dup( last_filename_root, "dup")

# ===========================  Step 5 : truncate  =============================
# Analyze.resave_sample( 2000, "#{ input_root}_fu_sopa_dup", "samp")


# ====================  Step 6 : output characteristics  ======================
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
providers = Analyze.get_list_of_residents( input_root ) # hash {"Jones" => [n_mon_thurs_pm_encounters, n_other]}

resident_names = providers.select {|k,v| 1.0 * v[0] / (v[0] + v[1]) > 0.9 }.collect {|k,v| k}

non_resident_names = providers.keys - resident_names
puts "==========================  resident_names  ============================"
puts " #{ resident_names }"
puts "========================  non_resident_names  =========================="
puts " #{ non_resident_names }"
training_fraction = 0.9
training_features, test_features = Analyze.extract_training_and_test_features_from_file(last_filename_root, training_fraction )


puts "Getting prototype features"
features_hash = (training_features + test_features).collect {|e| e.to_a}
   .flatten(1).uniq.group_by {|k,v| k}.collect do |feature_name, all_values|
      unique_values =  all_values.collect {|k,v| v}.uniq
   
      [feature_name, unique_values]
end


headers = ["feature", "resident", "non-resident"]
counts_by_feature_value = {}

training_features.each do |row|
   is_resident = resident_names.include?(row["provider"])
   
   row.each do |feature_name, v|
      
      counts_by_feature_value["#{feature_name}=#{v}"] ||= [0, 0]
      counts_by_feature_value["#{feature_name}=#{v}"][is_resident ? 0 : 1] += 1
      
   end
end

CSV.open("#{ output_root }_breakdown.csv", "wb") do |csv_out|
   csv_out << headers
   
   csv_out << ["names", resident_names.join(" | "), non_resident_names.join(" | ") ]
   features_hash.each do |feature_name, value_names|
      value_names.each do |v|
         counts_by_feature_value["#{feature_name}=#{v}"] ||= [0, 0]
         
         csv_out << [ "#{feature_name}=#{v}"] + counts_by_feature_value["#{feature_name}=#{v}"]
      end
   end
end


# =============================================================================
# ========================   assembling into instances   ======================

puts "done"
