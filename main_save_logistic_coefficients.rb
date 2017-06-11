# this script analyzes EPIC data

# exported from business objects… (PROMIS)

# =====================   GETTING STARTED INSTRUCTIONS   ====================
# use jruby-9.1.2.0 rather than ruby
# rbenv local jruby-9.1.2.0
# which has equivalence of ruby 2.3.0

# first run gem install weka (but first ensure that jruby is chosen)

recommend_ruby_version = "2.3.0"

puts "Warning: Running ruby version #{ RUBY_VERSION }. (Recommend #{ recommend_ruby_version })" unless recommend_ruby_version ==  RUBY_VERSION

require "csv"
require "./filters.rb"
# require "./reports.rb"
require "./analyze.rb"
# require 'statsample' # if cannot find statssample; run gem install statsample

require 'weka' # requires jruby
# https://github.com/paulgoetze/weka-jruby
# https://github.com/paulgoetze/weka-jruby/wiki


# =============================================================================
# ===============================  parameters  ================================
input_root = "neurology_provider_visits_with_payer_20170608"
timeslot_size = 15 # minutes
output_root = "logistic_classifier"
# stats_odds_ratios_filename = "stats_odds_ratios.csv"
# stats_odds_ratios_significant_filename = "stats_odds_ratios_significant.csv"
# provider_grouping_template_filename = "provider_groupings_template.csv"
# prediction_output_filename = "no_show_predictions.csv"
# validation_filename = "validation.csv"


# ======================  Step 1 : keep only follow ups  ======================
Analyze.resave_followups_only( input_root, "fu")

# =========================  Step 2 : eliminate dup  ==========================
# amongst completed encounters, eliminate the duplicate encounters associated 
# with Botox and EMG so we don't overcount minutes of patients seen
Analyze.resave_without_dup( "#{ input_root}_fu", "dup")

# =======================  Step 3 : truncate for now  =========================
Analyze.resave_sample( 2000, "#{ input_root}_fu_dup", "samp")

Analyze.output_characteristics( "#{ input_root}_fu_dup_samp", :except => [""] )


# =============================================================================
# Pecularities of the data
# - sometimes there is identical patient in a slot twice, one cancelled, and one completed
# - Botox and EMG can sometimes have duplicate, triplicate, or even 4x of
#   same patient, same timeslot, same visit type, same status (completed)
#   DOE,JOHN EMG (Completed 15) / DOE,JOHN EMG (Completed 15)



# =============================================================================
# ===========================   features analysis   ===========================

training_fraction = 0.8

valid_row_indexes = Array.new
n_read = 0
CSV.foreach( "#{ input_root}_fu_dup_samp.csv", headers: true ) do |row|
  item = Hash[row]
  
  if [item].status_completed.any? or [item].status_no_show.any?
    valid_row_indexes << n_read
  end
  n_read += 1
end
puts "  there are #{ valid_row_indexes.size} valid rows that will be divided"

puts "Separating into training and test sets"
training_indexes = valid_row_indexes.sample( (valid_row_indexes.size * training_fraction).round)
test_indexes = valid_row_indexes - training_indexes
puts "  There should be #{training_indexes.size} training and #{test_indexes.size} test instances"


puts "Extracting features for training and test sets"
training_features = Analyze.load_and_extract_features_from_encounters_file( "#{ input_root}_fu_dup_samp", training_indexes )
test_features = Analyze.load_and_extract_features_from_encounters_file( "#{ input_root}_fu_dup_samp", test_indexes )

puts "  Done. Extracted features for #{ training_features.size } training instances"


# ===========================   training the model   ==========================
# =====================  and calculation of odds ratios  ======================
puts "Getting prototype features"
features_hash = (training_features + test_features).collect {|e| e.to_a}.flatten(1).uniq.group_by {|k,v| k}.collect do |feature_name, all_values|
   unique_values =  all_values.collect {|k,v| v}.uniq
   
   [feature_name, unique_values]
end


puts "Creating instances prototype based on existing features"
puts "  Make sure these features are correct"

# create instances with relation name 'weather' and attributes
instances_prototype = Weka::Core::Instances.new(relation_name: 'encounter').with_attributes do
   features_hash.each do |feature_name, possible_values|

    
   if possible_values.size == 1
      # if possible_values == [1]
      #   possible_values += [0]
      # end
      puts "    Warning: #{ feature_name} only has a possible option of #{ possible_values }"
   else
      puts "    #{feature_name} has options #{ possible_values }"
   end
    
    
    
    nominal feature_name, values: possible_values # do not accept nils
  end

  # nominal :gender_male, values: [true, false]
  # nominal :no_show, values: [true, false]
  # numeric :temperature
  # numeric :humidity
  # nominal :windy, values: [true, false]
  # date    :last_storm, 'yyyy-MM-dd'
  # nominal :play, values: [:yes, :no], class_attribute: true
end

# puts "Features array looks like this"
# puts training_features.first(3)
# {"dist_km"=>"0064", "age_decade"=>"070", "gender"=>"male", "appt_made_d_advance"=>1, "dept"=>"neurology_pah", "appt_hour"=>"12", "appt_type"=>"return patient visit", "prior_show_past_2yr"=>0, "prior_no_show_past_2yr"=>0, "prior_cancellations_past_2yr"=>0, "outcome"=>"show"}
# {"dist_km"=>">=1024", "age_decade"=>"060", "gender"=>"female", "appt_made_d_advance"=>1, "dept"=>"neurology_hup", "appt_hour"=>"11", "appt_type"=>"return patient visit", "prior_show_past_2yr"=>0, "prior_no_show_past_2yr"=>0, "prior_cancellations_past_2yr"=>0, "outcome"=>"show"}
# {"dist_km"=>"0008", "age_decade"=>"040", "gender"=>"female", "appt_made_d_advance"=>1, "dept"=>"neurology_south_pavilion", "appt_hour"=>"16", "appt_type"=>"return patient visit", "prior_show_past_2yr"=>0, "prior_no_show_past_2yr"=>0, "prior_cancellations_past_2yr"=>0, "outcome"=>"show"}

puts "Converting features to instances for training data"
training_instances = Analyze.add_instances_from_encounters_array( training_features, instances_prototype.clone )
training_instances.class_attribute = :outcome
training_instances.to_csv("#{input_root}_training_instances.csv")



puts "Training the classifier"
# classifier = Weka::Classifiers::Trees::RandomForest.new
# classifier = Weka::Classifiers::Bayes::NaiveBayes.new
classifier = Weka::Classifiers::Functions::Logistic.new # 0.2978 RMS error
# classifier.use_options('-I 200 -K 5')
classifier.train_with_instances(training_instances)
puts "  Done"



puts "Converting features to instances for test data"
test_instances = Analyze.add_instances_from_encounters_array( test_features, instances_prototype.clone )
test_instances.class_attribute = :outcome
test_instances.to_csv("#{input_root}_test_instances.csv")
puts "  Done"

# future_instances = add_instances_from_encounters_array( all_future_encounters )


puts "Evaluating"
evaluation = classifier.evaluate(test_instances)
puts "  Done"

# =============================================================================
# ====================  Outputs some performance metrics  =====================
# RMS error should be less than 0.3
puts evaluation.summary
File.open("#{ output_root }_report.txt", 'w') { |file| 
   file.write """
================================  EVALUATION  =================================
#{ evaluation.summary }
   
============================  CLASSIFIER DETAILS  =============================
#{ classifier.globalInfo }

========================  CLASSIFIER TRAINING OUTCOME  ========================
#{ classifier.toString }   

===========================  TRAINING DATA DETAILS  ===========================
date: #{ Time.now }
input_root: #{ input_root }
training_fraction: #{ training_fraction}
training_features: #{ training_features.size } 
test_features: #{ test_features.size }

"""
}



# =============================================================================
# ========  An obnoxious process required to get the coeffiecients out  ========



coefficients = Analyze.get_logistic_coefficients_from_classifier( classifier, training_instances )

CSV.open("#{ output_root }_coefficients.csv", "wb") do |csv_out|
   csv_out << ["key", "value", "coefficient"]
   coefficients.each do |e|
      csv_out << e
   end
end

