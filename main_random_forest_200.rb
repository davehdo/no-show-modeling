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
output_root = "random_forest_classifier_i200"

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
instances_file_extension = "arff"

Analyze.check_overwrite("#{last_filename_root}_training_instances.#{instances_file_extension}") do

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
   training_instances.to_arff("#{last_filename_root}_training_instances.#{instances_file_extension}")


   puts "Converting features to instances for test data"
   test_instances = Analyze.add_instances_from_encounters_array( test_features, instances_prototype.clone )
   test_instances.class_attribute = :outcome
   test_instances.to_arff("#{last_filename_root}_test_instances.#{instances_file_extension}")
   puts "  Done"
   
end



# ===========================   training the model   ==========================
# =====================  and calculation of odds ratios  ======================
puts "Training the classifier"

# placed inside a method for scoping variables
def classifier_from_training( filename )
   classifier = Weka::Classifiers::Trees::RandomForest.new # default I is 100

   # I = the number of decision trees
   # N =  Number of folds for backfitting (default 0, no backfitting).
   # K = number of features to consider

   # http://weka.sourceforge.net/doc.dev/

   classifier.use_options('-I 150')
   # In addition to the parameters listed above for bagging, a key parameter for random forest is the number of attributes to consider in each split point. In Weka this can be controlled by the numFeatures attribute, which by default is set to 0, which selects the value automatically based on a rule of thumb.
   # raise classifier.globalInfo.inspect # RuntimeError: "Class for constructing a forest of random trees.\n\nFor more information see: \n\nLeo Breiman (2001). Random Forests. Machine Learning. 45(1):5-32."

   # raise classifier.getOptions.inspect # -I, 100, -K, 0, -S, 1, -num-slots, 1
   training_instances = Weka::Core::Instances.from_arff( filename )
   training_instances.class_attribute = :outcome
   classifier.train_with_instances(training_instances)
end

classifier = classifier_from_training( "#{last_filename_root}_training_instances.#{instances_file_extension}" )
puts "  Done"

# Error: Your application used more memory than the safety cap of 500M.
# Specify -J-Xmx####M to increase it (#### = cap size in MB).



puts "Evaluating"
test_instances = Weka::Core::Instances.from_arff("#{last_filename_root}_test_instances.#{instances_file_extension}")
test_instances.class_attribute = :outcome

evaluation = classifier.evaluate(test_instances)
puts "  Done"


# =============================================================================
# ====================  Outputs some performance metrics  =====================
# RMS error should be less than 0.3
puts classifier.getOptions.inspect
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



"""
}

 #
# e["features"] = {
#   "dist_km" => Analyze.categorize_continuous_var_by_boundaries(dist, (1..10).collect {|n| 2 ** n} ) || "UNKNOWN",
#   "age_decade" => Analyze.categorize_continuous_var_by_boundaries( e["Age at Encounter"].to_i, (10..90).step(10)) || "UNKNOWN",
#   "zip_code" => zip,
#   "gender" => e["Gender"].downcase == "male" ? "male" : "female",
#   "appt_made_d_advance" =>  Analyze.categorize_continuous_var_by_boundaries(e["appt_booked_on"] ? (e["appt_at"] - e["appt_booked_on"] ) : nil, (1..8).collect {|n| 2 ** n} ) || "UNKNOWN",
#   "dept" => e["Department"].downcase.gsub(" ", "_"),
#   "appt_hour" => e["appt_at"].hour.to_s.rjust(2, "0"),
#   "appt_type" => e["Visit Type"].downcase,
#   "last_contact" =>  Analyze.categorize_continuous_var_by_boundaries(e["contacted_on"] ? (e["appt_at"] - e["contacted_on"]) : nil, (1..8).collect {|n| 2 ** n} ) || "UNKNOWN",
#   "outcome" => [e].status_no_show.any? ? "no_show" : ([e].status_completed.any? ? "show" : nil),
#   "payer" => benefit_plan_category,
#   "prior_show_past_2yr" => e["prior_show_past_2yr"],
#   "prior_noshow_past_2yr" => e["prior_noshow_past_2yr"],
#   "prior_cancel_past_2yr" => e["prior_cancel_past_2yr"],
#   "session" => e["appt_at"].strftime("%a %p"),
#   # "provider" => e["Provider"]
# }.select {|k,v| v!=nil }
#

# when i = 50
#
# Correctly Classified Instances       10623               86.7396 %
# Incorrectly Classified Instances      1624               13.2604 %
# Kappa statistic                          0.0714
# Mean absolute error                      0.1959
# Root mean squared error                  0.3221
# Relative absolute error                 88.5288 %
# Root relative squared error             95.9575 %
# Coverage of cases (0.95 level)          98.2853 %
# Mean rel. region size (0.95 level)      81.5547 %
# Total Number of Instances            12247
# Davids-MacBook-Pro-4:no-show-modeling daviddo$


# when i = 100
# Correctly Classified Instances       10615               86.6743 %
# Incorrectly Classified Instances      1632               13.3257 %
# Kappa statistic                          0.0707
# Mean absolute error                      0.1955
# Root mean squared error                  0.3214
# Relative absolute error                 88.3511 %
# Root relative squared error             95.7467 %
# Coverage of cases (0.95 level)          98.3016 %
# Mean rel. region size (0.95 level)      81.5996 %
# Total Number of Instances            12247

# when i = 120
# Correctly Classified Instances       10616               86.6825 %
# Incorrectly Classified Instances      1631               13.3175 %
# Kappa statistic                          0.0717
# Mean absolute error                      0.1957
# Root mean squared error                  0.3214
# Relative absolute error                 88.4614 %
# Root relative squared error             95.7511 %
# Coverage of cases (0.95 level)          98.3751 %
# Mean rel. region size (0.95 level)      81.6731 %
# Total Number of Instances            12247
# Davids-MacBook-Pro-4:no-show-modeling daviddo$
#
#
# when classifier.use_options('-I 100 -K 5')
# Correctly Classified Instances       10594               86.5028 %
# Incorrectly Classified Instances      1653               13.4972 %
# Kappa statistic                          0.0899
# Mean absolute error                      0.1954
# Root mean squared error                  0.3233
# Relative absolute error                 88.2936 %
# Root relative squared error             96.3152 %
# Coverage of cases (0.95 level)          98.1383 %
# Mean rel. region size (0.95 level)      80.485  %
# Total Number of Instances            12247
# Davids-MacBook-Pro-4:no-show-modeling daviddo$

# when classifier.use_options('-I 100 -K 8')
# Correctly Classified Instances       10503               85.7598 %
# Incorrectly Classified Instances      1744               14.2402 %
# Kappa statistic                          0.1303
# Mean absolute error                      0.1936
# Root mean squared error                  0.3301
# Relative absolute error                 87.4818 %
# Root relative squared error             98.3322 %
# Coverage of cases (0.95 level)          97.4851 %
# Mean rel. region size (0.95 level)      76.876  %
# Total Number of Instances            12247

# classifier.use_options('-I 100 -K 12')
# Correctly Classified Instances       10352               84.5268 %
# Incorrectly Classified Instances      1895               15.4732 %
# Kappa statistic                          0.1513
# Mean absolute error                      0.1921
# Root mean squared error                  0.3425
# Relative absolute error                 86.8367 %
# Root relative squared error            102.0312 %
# Coverage of cases (0.95 level)          96.3828 %
# Mean rel. region size (0.95 level)      72.9036 %
# Total Number of Instances            12247
# Davids-MacBook-Pro-4:no-show-modeling daviddo$





# =============================================================================
# removed provider name as an attribute

#    classifier.use_options('-I 100')
# Correctly Classified Instances       10598               86.5425 %
# Incorrectly Classified Instances      1648               13.4575 %
# Kappa statistic                          0.0979
# Mean absolute error                      0.199
# Root mean squared error                  0.3278
# Relative absolute error                 89.5812 %
# Root relative squared error             97.126  %
# Coverage of cases (0.95 level)          97.9585 %
# Mean rel. region size (0.95 level)      80.8836 %
# Total Number of Instances            12246

# using only first 3 digits of zip
# classifier.use_options('-I 100')
# Correctly Classified Instances       10627               86.7794 %
# Incorrectly Classified Instances      1619               13.2206 %
# Kappa statistic                          0.0956
# Mean absolute error                      0.1972
# Root mean squared error                  0.3292
# Relative absolute error                 90.333  %
# Root relative squared error             99.8265 %
# Coverage of cases (0.95 level)          97.4359 %
# Mean rel. region size (0.95 level)      80.1445 %
# Total Number of Instances            12246

# java.lang.String[-I, 150, -K, 0, -S, 1, -num-slots, 1]@56193c7d
#
# Correctly Classified Instances       10625               86.763  %
# Incorrectly Classified Instances      1621               13.237  %
# Kappa statistic                          0.0944
# Mean absolute error                      0.1972
# Root mean squared error                  0.3289
# Relative absolute error                 90.3113 %
# Root relative squared error             99.7281 %
# Coverage of cases (0.95 level)          97.4686 %
# Mean rel. region size (0.95 level)      80.0384 %
# Total Number of Instances            12246

