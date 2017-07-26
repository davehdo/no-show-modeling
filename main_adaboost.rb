
# It is part of a group of ensemble methods called boosting, that add new machine learning models in a series where subsequent models attempt to fix the prediction errors made by prior models. AdaBoost was the first successful implementation of this type of model.




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
output_root = "adaboost_classifier_i200"

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
   only_features_named = [
      "age_decade", "zip_3", "gender", "dist_km", #, "zip_code", 
      "appt_made_d_advance", "dept", "appt_hour", "appt_type", 
      "outcome", "payer", "prior_show_past_2yr", "prior_noshow_past_2yr", 
      "prior_cancel_past_2yr", "session", "race" #, "provider"
   ]
   
   training_features, test_features = Analyze.extract_training_and_test_features_from_file(last_filename_root, training_fraction, only_features_named: only_features_named )

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
   classifier = Weka::Classifiers::Meta::AdaBoostM1.new # 
   
   # http://weka.sourceforge.net/doc.dev/

   # java.lang.String[-P, 100, -S, 1, -I, 10, -W, weka.classifiers.trees.DecisionStump]@28c88600

   classifier.use_options("-I 100 -S #{ (rand * 10).floor }")
   #
   # Valid options are:
   #  -P <num>   Percentage of weight mass to base training on.
   #        (default 100, reduce to around 90 speed up)
   #  -Q    Use resampling for boosting.
   #  -S <num>    Random number seed. (default 1)
   #  -I <num>    Number of iterations. (default 10)
   #  -D    If set, classifier is run in debug mode and may output additional info to the console
   #  -W    Full name of base classifier. (default: weka.classifiers.trees.DecisionStump)
   #
   #  Options specific to classifier weka.classifiers.trees.DecisionStump:
   #
   #  -D    If set, classifier is run in debug mode and may output additional info to the console
   #
   # raise classifier.getOptions.inspect # -I, 100, -K, 0, -S, 1, -num-slots, 1
   training_instances = Weka::Core::Instances.from_arff( filename )
   training_instances.class_attribute = :outcome
   classifier.train_with_instances(training_instances)
end

# call the above
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
puts "===============================  Result  ==============================="
puts "Features included in this analysis:"
puts test_instances.enumerateAttributes.collect {|e| e.name}.inspect
# puts test_instances.class
puts "Options for training this classifier"
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


# when using random forest with i = 100
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

# =======  when using adaboost with default options  =======
# java.lang.String[-P, 100, -S, 1, -I, 10, -W, weka.classifiers.trees.DecisionStump]@28c88600
#
# Correctly Classified Instances       10725               87.5796 %
# Incorrectly Classified Instances      1521               12.4204 %
# Kappa statistic                          0
# Mean absolute error                      0.2054
# Root mean squared error                  0.3203
# Relative absolute error                 94.0951 %
# Root relative squared error             97.1138 %
# Coverage of cases (0.95 level)         100      %
# Mean rel. region size (0.95 level)     100      %
# Total Number of Instances            12246


# -P, 100, -S, 1, -I, 25
# Correctly Classified Instances       10745               87.7429 %
# Incorrectly Classified Instances      1501               12.2571 %
# Kappa statistic                          0.0285
# Mean absolute error                      0.1976
# Root mean squared error                  0.3177
# Relative absolute error                 90.4949 %
# Root relative squared error             96.3219 %
# Coverage of cases (0.95 level)          99.461  %
# Mean rel. region size (0.95 level)      92.3689 %
# Total Number of Instances            12246

#
# java.lang.String[-P, 100, -S, 1, -I, 50, -W, weka.classifiers.trees.DecisionStump]@79b663b3
#
# Correctly Classified Instances       10745               87.7429 %
# Incorrectly Classified Instances      1501               12.2571 %
# Kappa statistic                          0.0498
# Mean absolute error                      0.1985
# Root mean squared error                  0.3159
# Relative absolute error                 90.9174 %
# Root relative squared error             95.7714 %
# Coverage of cases (0.95 level)          99.608  %
# Mean rel. region size (0.95 level)      93.5816 %
# Total Number of Instances            12246




# java.lang.String[-P, 100, -S, 5, -I, 50, -W, weka.classifiers.trees.DecisionStump]@79b663b3
#
# Correctly Classified Instances       10745               87.7429 %
# Incorrectly Classified Instances      1501               12.2571 %
# Kappa statistic                          0.0498
# Mean absolute error                      0.1985
# Root mean squared error                  0.3159
# Relative absolute error                 90.9174 %
# Root relative squared error             95.7714 %
# Coverage of cases (0.95 level)          99.608  %
# Mean rel. region size (0.95 level)      93.5816 %
# Total Number of Instances            12246



#
# java.lang.String[-P, 100, -S, 4, -I, 100, -W, weka.classifiers.trees.DecisionStump]@1b812421
#
# Correctly Classified Instances       10749               87.7756 %
# Incorrectly Classified Instances      1497               12.2244 %
# Kappa statistic                          0.0586
# Mean absolute error                      0.1973
# Root mean squared error                  0.3152
# Relative absolute error                 90.3876 %
# Root relative squared error             95.5612 %
# Coverage of cases (0.95 level)          99.5509 %
# Mean rel. region size (0.95 level)      92.1035 %
# Total Number of Instances            12246

#
#
# java.lang.String[-P, 100, -S, 1, -I, 1000, -W, weka.classifiers.trees.DecisionStump]@1b812421
#
# Correctly Classified Instances       10751               87.7919 %
# Incorrectly Classified Instances      1495               12.2081 %
# Kappa statistic                          0.0712
# Mean absolute error                      0.1965
# Root mean squared error                  0.315
# Relative absolute error                 89.9825 %
# Root relative squared error             95.5124 %
# Coverage of cases (0.95 level)          99.4202 %
# Mean rel. region size (0.95 level)      91.14   %
# Total Number of Instances            12246


# -P, 100, -S, 1, -I, 1000
#
# Correctly Classified Instances       10733               87.6378 %
# Incorrectly Classified Instances      1514               12.3622 %
# Kappa statistic                          0.082
# Mean absolute error                      0.1935
# Root mean squared error                  0.3128
# Relative absolute error                 88.1444 %
# Root relative squared error             94.1813 %
# Coverage of cases (0.95 level)          99.3304 %
# Mean rel. region size (0.95 level)      88.2828 %
# Total Number of Instances            12247

#
# ===============================  Result  ===============================
# Features included in this analysis:
# ["age_decade", "zip_3", "gender", "appt_made_d_advance", "dept", "appt_hour", "appt_type", "payer", "session", "race", "provider", "prior_show_past_2yr", "prior_noshow_past_2yr", "prior_cancel_past_2yr"]
# Options for training this classifier
# java.lang.String[-P, 100, -S, 9, -I, 100, -W, weka.classifiers.trees.DecisionStump]@794b435f
#
# Correctly Classified Instances       10732               87.6296 %
# Incorrectly Classified Instances      1515               12.3704 %
# Kappa statistic                          0.0665
# Mean absolute error                      0.1948
# Root mean squared error                  0.314
# Relative absolute error                 88.7618 %
# Root relative squared error             94.5393 %
# Coverage of cases (0.95 level)          99.4203 %
# Mean rel. region size (0.95 level)      90.1119 %
# Total Number of Instances            12247
#
# ===============================  Result  ===============================
# Features included in this analysis:
# ["age_decade", "zip_3", "gender", "appt_made_d_advance", "dept", "appt_hour", "appt_type", "payer", "session", "race", "prior_show_past_2yr", "prior_noshow_past_2yr", "prior_cancel_past_2yr"] ( removed provider)
# Options for training this classifier
# java.lang.String[-P, 100, -S, 4, -I, 100, -W, weka.classifiers.trees.DecisionStump]@36912b0
#
# Correctly Classified Instances       10774               87.9726 %
# Incorrectly Classified Instances      1473               12.0274 %
# Kappa statistic                          0.0809
# Mean absolute error                      0.1934
# Root mean squared error                  0.3129
# Relative absolute error                 88.5527 %
# Root relative squared error             94.8179 %
# Coverage of cases (0.95 level)          99.2325 %
# Mean rel. region size (0.95 level)      90.6549 %
# Total Number of Instances            12247

#
# ===============================  Result  ===============================
# Features included in this analysis:
# ["dist_km", "age_decade", "zip_3", "gender", "appt_made_d_advance", "dept", "appt_hour", "appt_type", "payer", "session", "race", "prior_show_past_2yr", "prior_noshow_past_2yr", "prior_cancel_past_2yr"] (add dist_km)
# Options for training this classifier
# java.lang.String[-P, 100, -S, 7, -I, 100, -W, weka.classifiers.trees.DecisionStump]@7fe8cd9a
#
# Correctly Classified Instances       10735               87.6541 %
# Incorrectly Classified Instances      1512               12.3459 %
# Kappa statistic                          0.0702
# Mean absolute error                      0.1941
# Root mean squared error                  0.3152
# Relative absolute error                 88.3774 %
# Root relative squared error             94.8084 %
# Coverage of cases (0.95 level)          99.3958 %
# Mean rel. region size (0.95 level)      90.5528 %
# Total Number of Instances            12247