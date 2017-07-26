# ruby -J-Xmx9000M main_random_forest_100.rb 


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
output_root = "random_forest_classifier_i100"

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

training_fraction = 0.8
training_features, test_features = Analyze.extract_training_and_test_features_from_file(last_filename_root, training_fraction )

puts "Getting prototype features"
features_hash = (training_features + test_features).collect {|e| e.to_a}
   .flatten(1).uniq.group_by {|k,v| k}.collect do |feature_name, all_values|
      unique_values =  all_values.collect {|k,v| v}.uniq
   
      [feature_name, unique_values]
end


puts "Creating instances prototype based on existing features"
puts "  Make sure these features are correct"

# create instances with relation name 'weather' and attributes
instances_prototype = Weka::Core::Instances.new(relation_name: 'encounter').with_attributes do
   features_hash.each do |feature_name, possible_values|    
      if possible_values.size == 1
         puts "    ** Warning: #{ feature_name } only has a possible option of #{ possible_values }"
      else
         puts "    #{feature_name} has options #{ possible_values }"
      end

      nominal feature_name, values: possible_values # do not accept nils
   end

   # nominal :gender_male, values: [true, false]
   # numeric :temperature
   # date    :last_storm, 'yyyy-MM-dd'
   # nominal :play, values: [:yes, :no], class_attribute: true
end

# Features array looks like this
# {"dist_km"=>"0064", "age_decade"=>"070", "gender"=>"male", "appt_made_d_advance"=>1, "dept"=>"neurology_pah", "appt_hour"=>"12", "appt_type"=>"return patient visit", "prior_show_past_2yr"=>0, "prior_no_show_past_2yr"=>0, "prior_cancellations_past_2yr"=>0, "outcome"=>"show"}


puts "Converting features to instances for training data"
training_instances = Analyze.add_instances_from_encounters_array( training_features, instances_prototype.clone )
training_instances.class_attribute = :outcome
training_instances.to_csv("#{input_root}_training_instances.csv")


puts "Converting features to instances for test data"
test_instances = Analyze.add_instances_from_encounters_array( test_features, instances_prototype.clone )
test_instances.class_attribute = :outcome
test_instances.to_csv("#{input_root}_test_instances.csv")
puts "  Done"

# future_instances = add_instances_from_encounters_array( all_future_encounters )

# Analyze.check_overwrite("#{input_root}_training_instances.csv") do
#
# end
# ===========================   training the model   ==========================
# =====================  and calculation of odds ratios  ======================


puts "Training the classifier"
classifier = Weka::Classifiers::Trees::RandomForest.new # default I is 100

# i think I is the number of decision trees
# N =  Number of folds for backfitting (default 0, no backfitting).
# K = 

# http://weka.sourceforge.net/doc.dev/

classifier.use_options('-I 100')
# In addition to the parameters listed above for bagging, a key parameter for random forest is the number of attributes to consider in each split point. In Weka this can be controlled by the numFeatures attribute, which by default is set to 0, which selects the value automatically based on a rule of thumb.
# raise classifier.globalInfo.inspect # RuntimeError: "Class for constructing a forest of random trees.\n\nFor more information see: \n\nLeo Breiman (2001). Random Forests. Machine Learning. 45(1):5-32."

# raise classifier.getOptions.inspect # -I, 100, -K, 0, -S, 1, -num-slots, 1




classifier.train_with_instances(training_instances)
puts "  Done"

# Error: Your application used more memory than the safety cap of 500M.
# Specify -J-Xmx####M to increase it (#### = cap size in MB).



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
# ========  An obnoxious process required to get the coeffiecients out  =======

# coefficients = Analyze.get_logistic_coefficients_from_classifier( classifier, training_instances )

# coefficients = classifier.getConditionalEstimators

# puts coefficients.inspect
#
# CSV.open("#{ output_root }_coefficients.csv", "wb") do |csv_out|
#    csv_out << ["key", "value", "coefficient"]
#    coefficients.each do |e|
#       csv_out << e
#    end
# end
#

# Ran this on 7/24/2017
# when i = 100

# Correctly Classified Instances       10652               86.9764 %
# Incorrectly Classified Instances      1595               13.0236 %
# Kappa statistic                          0.0701
# Mean absolute error                      0.1952
# Root mean squared error                  0.3191
# Relative absolute error                 88.867  %
# Root relative squared error             95.9506 %
# Coverage of cases (0.95 level)          98.4486 %
# Mean rel. region size (0.95 level)      82.5835 %
# Total Number of Instances            12247
# Davids-MacBook-Pro-4:no-show-modeling daviddo$
