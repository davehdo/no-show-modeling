# this script analyzes billing reports
# Report is calling “Charges, Payments and Adjustments”
# exported from business objects… (PROMIS)

# =====================   GETTING STARTED INSTRUCTIONS   ====================
# use jruby-9.1.2.0 rather than ruby
# rbenv local jruby-9.1.2.0
# which has equivalence of ruby 2.3.0

# first run gem install weka (but first ensure that jruby is chosen)

recommend_ruby_version = "2.3.0"

puts "Warning: Running ruby version #{  RUBY_VERSION }. (Recommend #{ recommend_ruby_version })" unless recommend_ruby_version ==  RUBY_VERSION

require "csv"
require "./filters.rb"
require "./reports.rb"
require "./analyze.rb"
# require 'yaml'


# require 'statsample' # if cannot find statssample; run gem install statsample

require 'weka' # requires jruby
# https://github.com/paulgoetze/weka-jruby
# https://github.com/paulgoetze/weka-jruby/wiki

# puts Weka::Classifiers::Trees::RandomForest.options
# puts Weka::Classifiers::Trees::RandomForest.description


# =============================================================================
# ===============================  parameters  ================================
input_file = "neurologyvisitsjuly2014-november2017_truncated.csv"
timeslot_size = 15 # minutes
stats_odds_ratios_filename = "stats_odds_ratios.csv"
stats_odds_ratios_significant_filename = "stats_odds_ratios_significant.csv"
provider_grouping_template_filename = "provider_groupings_template.csv"
prediction_output_filename = "no_show_predictions.csv"
validation_filename = "validation.csv"


# =============================================================================
# ============================   load data file   =============================

puts "Loading data file #{ input_file }"
@encounters_all = CSV.read(input_file, {headers: true}) # returns a CSV::Table
  
puts "  Loaded; there are #{ @encounters_all.size} rows"
raise @encounters_all.class.inspect


# =============================================================================
# ===========================   remove duplicates  ============================
# Pecularities of the data
# - sometimes there is identical patient in a slot twice, one cancelled, and one completed
# - Botox and EMG can sometimes have duplicate, triplicate, or even 4x of
#   same patient, same timeslot, same visit type, same status (completed)
#   DOE,JOHN EMG (Completed 15) / DOE,JOHN EMG (Completed 15)

# amongst completed encounters, eliminate the duplicate encounters associated 
# with Botox and EMG so we don't overcount minutes of patients seen
# 
@encounters_all = @encounters_all
  .select {|e| e["Appt Status"] == "Completed"}
  .uniq {|e| "#{ e["MRN"]}|#{e["Appt. Time"]}|#{ e["Appt. Length"] }|#{ e["Visit Type"] }"} +
  @encounters_all.select {|e| e["Appt Status"] != "Completed"}

  puts "  After duplicate-removal there are #{ @encounters_all.size } rows"


# =============================================================================
# =======================  output a table of providers  =======================
#
# puts "Generating provider list and saving as --#{ provider_grouping_template_filename }--"
# CSV.open("#{ provider_grouping_template_filename }", "wb") do |csv|
#   csv << ["PROV_NAME", "N_ENCOUNTERS", "INCLUDE_IN_TRAINING_SET", "GENERATE_REPORT"]
#   @encounters_all.group_by {|e| e["Provider"]}.each do |prov_name, e|
#     csv << [prov_name, e.size, nil, nil]
#   end
# end
# puts "  done"
#
# =============================================================================
# ============================   fix timestamps   =============================

puts "Parsing timestamps"
@encounters_all.each {|e| 
  e["appt_at"] = DateTime.strptime(e["Appt. Time"], ' %m/%d/%Y  %H:%M ')
  e["checkin_time_obj"] = DateTime.strptime(e["Checkin Time"], ' %m/%d/%Y  %H:%M ') if e["Checkin Time"]
  e["clinic_session"] = "#{ e["Provider"]}|#{ e["appt_at"].strftime("%F|%p") }"
  e["contacted_on"] = DateTime.strptime( e["Contact Date"], " %m/%d/%Y") if e["Contact Date"]
  # begin
  #   e["appt_booked_on"] = DateTime.strptime(e["Appt. Booked on"], "%m/%d/%y") if e["Appt. Booked on"]
  #   e["appt_booked_on"] = nil if e["appt_booked_on"] > e["appt_at"]
  # rescue
  #   false
  # end
    
  # e.g. timeslot   KIMBARIS, GRACE CHEN|2014-09-18|13:15
  e["timeslots"] = (0...(e["Appt. Length"].to_i)).step(timeslot_size).collect {|interval| 
    timeslot = e["appt_at"] + (interval / 24.0 / 60.0)
    "#{ e["Provider"]}|#{ timeslot.strftime("%F|%H:%M") }"  
  }
  puts "  Warning: prov has #{ e["Appt. Length"] } min appt but our analysis uses #{ timeslot_size } min timeslots (#{e["timeslots"]})" if (1.0 * e["Appt. Length"].to_i / timeslot_size).to_i != e["timeslots"].size
  
}
puts "  done"

# =============================================================================
# ==================   extract features for each encounter   ==================
puts "Extracting features"

puts "  Loading zip code data"
distance_by_zip = Hash[CSV.read("zipcode_distances_from_19104.csv", {headers: true}).collect {|e| [e["ZIP"], e["DIST_KM"].to_f]}]
puts "    Loaded"

# in order to find specific patient's prior encounters
encounters_by_mrn = @encounters_all.group_by {|e| e["MRN"]}


@encounters_all.each {|e| 
  # features
  prior_encounters_2_yrs = encounters_by_mrn[e["MRN"]].select {|f| f["appt_at"] > (e["appt_at"] - 730) and f["appt_at"] < e["appt_at"] }
  
  n_prior_encounters_show = prior_encounters_2_yrs.status_completed.size
  n_prior_encounters_no_show = prior_encounters_2_yrs.status_no_show.size
  n_prior_encounters_cancelled = prior_encounters_2_yrs.status_cancelled.size
  
  # n_prior_encounters_show > 5 ? ">5" : n_prior_encounters_show
  # n_prior_encounters_no_show > 5 ? ">5" : n_prior_encounters_no_show
  # n_prior_encounters_cancelled > 5 ? ">5" : n_prior_encounters_cancelled
  
  zip = e["Zip Code"] ? e["Zip Code"][0..4].rjust(5, "0") : "absent"
  dist = distance_by_zip[ zip ]   # distance from hosp

  # we do a sparse encoding -- anything not listed in features is assumed to be 0

  e["features"] = {
    "dist_km" => Analyze.categorize_continuous_variable_log(dist, 2, 4, 0, 1024),
    "age_decade" => Analyze.categorize_continuous_variable( e["Age at Encounter"].to_i, 10, 3, 10, 90),
    # "zip_#{ zip }" => 1,
    "gender" => e["Gender"].downcase == "male" ? "male" : "female",
    "appt_made_#{ Analyze.categorize_continuous_variable_log(e["appt_booked_on"] ? (e["appt_at"] - e["appt_booked_on"] + 1) : nil, 2, 4, 0, 256 )  }d_advance" => 1,
    "dept" => e["Department"].downcase.gsub(" ", "_"),
    "appt_hour" => e["appt_at"].hour.to_s.rjust(2, "0"),
    "appt_type" => e["Visit Type"].downcase,
    "prior_show_past_2yr" =>  n_prior_encounters_show,
    "prior_no_show_past_2yr" => n_prior_encounters_no_show,
    "prior_cancellations_past_2yr" => n_prior_encounters_cancelled,
    # "prior_show_past_2yr_#{ n_prior_encounters_show.to_s.rjust(2, "0") }" => 1,
    # "prior_no_show_past_2yr_#{ n_prior_encounters_no_show.to_s.rjust(2, "0") }" => 1,
    # "prior_cancellations_past_2yr_#{ n_prior_encounters_cancelled.to_s.rjust(2, "0") }" => 1,
    "outcome" => [e].status_no_show.any? ? "no_show" : ([e].status_completed.any? ? "show" : nil)
  }.select {|k,v| v!=nil }

}
puts "  done"

# get back some memory
encounters_by_mrn = nil
distance_by_zip = nil

# =============================================================================
# ===========================   features analysis   ===========================
# ===========================   training the model   ==========================
# =====================  and calculation of odds ratios  ======================

training_fraction = 0.25

puts "Separating into training and test sets"
puts "  Finding all past encounters"
test_set = @encounters_all.status_completed + @encounters_all.status_no_show

puts "  Assigning a training as a subset"
training_set = test_set.sample( (test_set.size * training_fraction).round)

puts "  Putting the remainder in the test set"
test_set -= training_set

# all_future_encounters = @encounters_all.status_scheduled
puts "  Assembling a list of the features"

features_hash = @encounters_all.collect {|e| e["features"].to_a}.flatten(1).uniq.group_by {|k,v| k}

puts "  Creating instances prototype based on existing features"

# create instances with relation name 'weather' and attributes
instances_prototype = Weka::Core::Instances.new(relation_name: 'encounter').with_attributes do
  features_hash.each do |feature_name, all_values|
    possible_values =  all_values.collect {|k,v| v}.uniq.compact
    
    if possible_values.size == 1
      if possible_values == [1]
        possible_values += [0]
      else
        puts "Warning: #{ feature_name} only has a possible value of #{ possible_values }"
      end
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

# get back some memory
features_hash = nil


def add_instances_from_encounters_array( encounters, instances )
  puts "There are #{encounters.size} encounters"
  feature_names = instances.attributes.collect {|e| e.name }
  
  puts "  feature names #{ feature_names }"
  data = encounters.collect do |encounter|
    # because many of the features fields are sparsely encoded, we fill in nils with zero
    feature_names.collect {|feature_name| x=encounter["features"][feature_name]; x.nil? ? 0 : x }
  end

  instances.add_instances(data) # , weight: 2.0
  instances
end

puts "Assembling the training and test instances"
training_instances = add_instances_from_encounters_array( training_set, instances_prototype.clone )
training_instances.class_attribute = :outcome
# training_instances.to_csv('encounters_training.csv')
#
test_instances = add_instances_from_encounters_array( test_set, instances_prototype.clone )
test_instances.class_attribute = :outcome
# training_instances.to_csv('encounters_test.csv')

puts "  Done"

# future_instances = add_instances_from_encounters_array( all_future_encounters )


puts "Training the classifier"
# classifier = Weka::Classifiers::Trees::RandomForest.new
# classifier = Weka::Classifiers::Bayes::NaiveBayes.new
classifier = Weka::Classifiers::Functions::Logistic.new # 0.2978 RMS error
# classifier.use_options('-I 200 -K 5')
classifier.train_with_instances(training_instances)
puts "  Done"


puts "Evaluating"
evaluation = classifier.evaluate(test_instances)

puts "  Done"
puts evaluation.summary

# class_attr_i = unique_feature_names.index("status") #
# /Users/***/.rbenv/versions/jruby-9.1.2.0/lib/ruby/gems/shared/gems/weka-0.4.0-java/lib/weka/core/attribute.rb 
# answers = test_instances.collect do |instance|
#   [
#     instance.values[class_attr_i] == "no_show",
#     classifier.classify(instance) == "no_show",
#     classifier.distribution_for(instance)["true"]
#   ] # actual, estimated, pct
# end
#
# pct_no_show = 1.0 * answers.count {|e| e[0] } / answers.size
#
# puts "% true positive: #{ 1.0 * answers.count {|e| e[0]  and e[1] } / answers.size }"
# puts "% true negative: #{ 1.0 * answers.count {|e| !e[0] and !e[1] } / answers.size }"
# puts "% false positive: #{ 1.0 * answers.count {|e| !e[0]  and e[1] } / answers.size }"
# puts "% false negative: #{ 1.0 * answers.count {|e| e[0]  and !e[1] } / answers.size }"
# puts "% actual no show: #{ pct_no_show }"
# puts "% predicted as no show: #{ 1.0 * answers.count {|e| e[1] } / answers.size }"
# puts "rms error (classified): #{ Math.sqrt(answers.collect {|e| ((e[0] ? 1.0 : 0.0) - (e[1] ? 1.0 : 0.0)) ** 2}.mean) }"
# puts "rms error (probabilistic): #{ Math.sqrt(answers.collect {|e| ((e[0] ? 1.0 : 0.0) - e[2]) ** 2}.mean) }"
# puts "rms error if constant prob used for all: #{ Math.sqrt(answers.collect {|e| ((e[0] ? 1.0 : 0.0) - pct_no_show) ** 2}.mean) } "
# =============================================================================
# ==============  assign each encounter a probability of no-show  =============



# apply prediction to future encounters
# raw_results = classifier.distributionsForInstances( future_instances )
#
# future_predictions = all_future_encounters.zip(raw_results)



# outputs the coefficient and odds ratio tables
puts classifier.toString

# puts "conditional estimators"
# puts classifier.getConditionalEstimators.inspect

puts "options"
puts classifier.getOptions

puts "coef"
coeffs = classifier.coefficients.collect {|e| e.collect {|f| f.to_f} }


# puts "distributions"

# puts coeff.inspect

import 'weka.filters.unsupervised.attribute.RemoveUseless'
java_import 'weka.filters.Filter'

logit_filter = RemoveUseless.new 
logit_filter.setInputFormat training_instances
logit_filtered = Filter.useFilter(training_instances, logit_filter) # class instances


# java_array = classifier.coefficients.to_a #converting java array to ruby
# coeffs = java_array.map(&:to_a) #converting second level of java array to ruby
# puts logit_filtered.inspect
attr_val_pairs = logit_filtered.attributes.collect {|attr| 
  vals = attr.enumerateValues.collect {|f| f}
  (vals.size == 2 ? [vals.last] : vals).collect {|f| [attr.name, f]}
}.flatten(1)


puts "there are #{ coeffs.size } coefficients and #{ attr_val_pairs.size } attr_val_pairs"

puts ([["Intercept", ""]] + attr_val_pairs).zip( coeffs.collect(&:first) ).inspect
# puts coeffs.zip( logit_filtered)
#   next if index == 0 #this is the Intercept
#   puts "#{logit_filtered.attribute(index-1).name.to_s}: #{coeffs}"
# end

# puts (instances_prototype.attributes.collect {|e| e.name } + ["Constant"]).zip(coeff).inspect



# rb=ReportBuilder.new
#
# a = answers.collect {|e| e[2]}.to_vector
# rb.add(Statsample::Graph::Histogram.new(a))
#
# b = answers.select {|e| e[0]}.collect {|e| e[2]}.to_vector
# rb.add(Statsample::Graph::Histogram.new(b))
#
# rb.save_html('histogram.html')



# =============================================================================
# =========================   validate the model   ============================
# squares = test_no_show.collect {|e| (1.0 - e[:prob_no_show]) ** 2 } +
#   test_show.collect {|e| (0.0 - e[:prob_no_show]) ** 2 }
#
# rms_error = Math.sqrt(squares.mean)
# puts "a validation was performed at RMS error of #{ rms_error }"


# threshold_of_no_show = 1 - 0.74 # greater than

# puts "with a threahold of #{ threshold_of_no_show }, the accuracy of prediction was #{ }"
# step_size = 0.015
#
# puts "Saving as --#{ validation_filename }--"
# CSV.open("#{ validation_filename }", "wb") do |csv|
#   csv << ["RMS error", rms_error]
#   csv << ["P(predicted no show) lower range", "P(actual no show)", "n show", "n no show"]
#
#   (0.0..0.8).step( 0.025 ).each do |prob|
#     n_no_show = @encounters_all.status_no_show.count {|e| ( prob...(prob + step_size) ).include? e[:prob_no_show] }
#     n_show = @encounters_all.status_completed.count {|e| ( prob...(prob + step_size) ).include? e[:prob_no_show] }
#
#     csv << [prob, 1.0 * n_no_show / ( n_no_show + n_show ), n_no_show, n_show]
#   end
# end

# =============================================================================
# ==============================   check data  ================================
# # e.g. 16:00  X,MARYANNE (Completed) / X,MARYANNE (Canceled) / X,JULIANNE (Canceled)
# @encounters_all.group_by {|e| "#{e["appt_at"].iso8601}" }.each {|timeslot, e|
#   if e.status_completed.size > 1
#     puts "Warning: multiple completed appointments at #{ timeslot }"
#   end
# }.flatten


# 2014-07-01T08:00 to 2017-04-28T16:30

# puts appt_times.min.inspect
# puts appt_times.max.inspect
# puts DateTime.strptime(appt_times.min, ' %m/%d/%Y  %H:%M ').inspect
# raise @encounters_all.collect {|e| e["Patient Class"]}.uniq.inspect

# =============================================================================
# ==========================   generate reports   =============================
#
# # puts Reports.sessions(selected_entries, clinic_sessions)
# def friendly_filename( input_string )
#   input_string.gsub(/[^0-9A-Za-z.\-]+/, '_').downcase
# end
#
#
# def generate_and_save_sessions_report( provider, encounters, custom_filename = nil) #
#   raise "no entries" if encounters.size == 0
#   puts "Producing report..."
#   clinic_sessions = Analyze.extract_clinic_sessions( encounters )
#
#   friendly = friendly_filename( custom_filename || provider )
#   filename_complete = "report_billing_#{friendly}_#{ Time.now.strftime("%F") }.txt"
#
#   File.open(filename_complete , "w:UTF-8") do |file|
#     file.write(Reports.sessions(encounters, clinic_sessions ).gsub("\n", "\r\n"))
#   end
#   puts "  Saved as #{ filename_complete }"
#
#   # filename_complete_2 = "report_prediction_#{friendly}_#{ Time.now.strftime("%F") }.txt"
#   #
#   # File.open(filename_complete_2 , "w:UTF-8") do |file|
#   #   file.write(Reports.sessions_prediction(encounters, clinic_sessions ).gsub("\n", "\r\n"))
#   # end
#   # puts "  Saved as #{ filename_complete_2 }"
#
# end
#
#
# selected_entries = @encounters_all.select {|e| e["Provider"] == "PRICE, RAYMOND"}
#   .select {|e| e["appt_at"] > DateTime.new(2016, 7, 1) and e["appt_at"] < DateTime.new(2017, 7, 1)}
#   # .sort_by {|e| e["appt_at"]}
#
# generate_and_save_sessions_report( "PRICE, RAYMOND", selected_entries)
# generate_and_save_sessions_report( "many providers", @encounters_all
#   .select {|e| e["appt_at"] > DateTime.new(2016, 7, 1) and e["appt_at"] < DateTime.new(2017, 7, 1)})
#
# generate_and_save_sessions_report( "DO, DAVID", @encounters_all
# .select {|e| e["Provider"] == "DO, DAVID"}
# .select {|e| e["appt_at"] > DateTime.new(2016, 7, 1) and e["appt_at"] < DateTime.new(2017, 7, 1)})
#
#
#
#
# # =============================================================================
# # ==============================   output   ===================================
#
# headers = ["appt_at", "Provider", "Patient Name", "Visit Type", "Appt Status"]
#
# puts "Saving as --#{ prediction_output_filename }--"
# CSV.open("#{ prediction_output_filename }", "wb") do |csv|
#   csv << headers + ["p1", "p2"]
#   future_predictions.each do |item, probability|
#     csv << [headers.collect {|header| item[header] }] + [probability[0], probability[1]]
#   end
# end
