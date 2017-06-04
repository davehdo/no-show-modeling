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


# begin
#   require 'statsample'
# rescue
#   puts "cannot find statssample; run gem install statsample"
# end

require 'weka' # requires jruby

# puts Weka::Classifiers::Trees::RandomForest.options
# puts Weka::Classifiers::Trees::RandomForest.description


# =============================================================================
# ===============================  parameters  ================================
input_file = "neurologyvisitsjuly2014-november2017.csv"
timeslot_size = 15 # minutes
stats_odds_ratios_filename = "stats_odds_ratios.csv"
stats_odds_ratios_significant_filename = "stats_odds_ratios_significant.csv"
provider_grouping_template_filename = "provider_groupings_template.csv"
prediction_output_filename = "no_show_predictions.csv"
validation_filename = "validation.csv"


# =============================================================================
# ============================   load data file   =============================

puts "Loading data file #{ input_file }"
@encounters_all = CSV.read(input_file, {headers: true})
  .select {|e| ["return patient visit", "new patient visit"].include? e["Visit Type"].downcase}
  .select {|e| e["Department"].downcase == "neurology south pavilion"}
  
puts "  Loaded; there are #{ @encounters_all.size} rows"

puts "Loading zip code data"
distance_by_zip = Hash[CSV.read("zipcode_distances_from_19104.csv", {headers: true}).collect {|e| [e["ZIP"], e["DIST_KM"].to_f]}]
puts "  Loaded"


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

puts "Generating provider list and saving as --#{ provider_grouping_template_filename }--"
CSV.open("#{ provider_grouping_template_filename }", "wb") do |csv|
  csv << ["PROV_NAME", "N_ENCOUNTERS", "INCLUDE_IN_TRAINING_SET", "GENERATE_REPORT"]
  @encounters_all.group_by {|e| e["Provider"]}.each do |prov_name, e| 
    csv << [prov_name, e.size, nil, nil]
  end
end  
puts "  done"
  
# =============================================================================
# ============================   fix timestamps   =============================

puts "Parsing timestamps"
@encounters_all.each {|e| 
  e["appt_at"] = DateTime.strptime(e["Appt. Time"], ' %m/%d/%Y  %H:%M ')
  e["checkin_time_obj"] = DateTime.strptime(e["Checkin Time"], ' %m/%d/%Y  %H:%M ') if e["Checkin Time"]
  e["clinic_session"] = "#{ e["Provider"]}|#{ e["appt_at"].strftime("%F|%p") }"
  e["contacted_on"] = DateTime.strptime( e["Contact Date"], " %m/%d/%Y") if e["Contact Date"]
  begin
    e["appt_booked_on"] = DateTime.strptime(e["Appt. Booked on"], "%m/%d/%y") if e["Appt. Booked on"]
    e["appt_booked_on"] = nil if e["appt_booked_on"] > e["appt_at"] 
  rescue
    false
  end
    
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

  # e["features"] = {
  #   "zip_#{ zip }" => 1,
  # } #.select {|k,v| k!=nil and (v == 1 or v == true)}
  
  e["features"] = {
    "dist_#{ Analyze.categorize_continuous_variable_log(dist, 2, 4, 0, 1024) }_km" => 1,
    "age_decade_#{ Analyze.categorize_continuous_variable( e["Age at Encounter"].to_i, 10, 3, 10, 90)  }" => 1,
    # "zip_#{ zip }" => 1,
    "gender_male" => e["Gender"].downcase == "male" ? 1 : 0,
    "appt_made_#{ Analyze.categorize_continuous_variable_log(e["appt_booked_on"] ? (e["appt_at"] - e["appt_booked_on"] + 1) : nil, 2, 4, 0, 256 )  }d_advance" => 1,
    # "dept_#{ e["Department"].downcase.gsub(" ", "_") }" => 1,
    "appt_hour_#{ e["appt_at"].hour.to_s.rjust(2, "0") }" => 1,
    "appt_type_#{ e["Visit Type"].downcase }" => 1,
    # "prior_show_past_2yr" =>  n_prior_encounters_show,
    # "prior_no_show_past_2yr" => n_prior_encounters_no_show,
    # "prior_cancellations_past_2yr" => n_prior_encounters_cancelled,
    "prior_show_past_2yr_#{ n_prior_encounters_show.to_s.rjust(2, "0") }" => 1,
    "prior_no_show_past_2yr_#{ n_prior_encounters_no_show.to_s.rjust(2, "0") }" => 1,
    "prior_cancellations_past_2yr_#{ n_prior_encounters_cancelled.to_s.rjust(2, "0") }" => 1,
    "no_show" => [e].status_no_show.any? ? true : ([e].status_completed.any? ? false : nil)
  }.select {|k,v| v!=nil }

  e["features"].delete("dist__km")

  
}
puts "  done"

# =============================================================================
# ===========================   features analysis   ===========================
# ===========================   training the model   ==========================
# =====================  and calculation of odds ratios  ======================

puts "Separating into training and test sets"

training_fraction = 0.4
# all_show = @encounters_all.status_completed
# all_no_show = @encounters_all.status_no_show
#
# training_show = all_show.sample( (all_show.size * training_fraction).round)
# training_no_show = all_no_show.sample( (all_no_show.size * training_fraction).round)
# test_show = all_show - training_show
# test_no_show = all_no_show - training_no_show

all = @encounters_all.status_completed + @encounters_all.status_no_show

training_set = all.sample( (all.size * training_fraction).round)
test_set = all - training_set


# ======================   method 1

# lr_model = Analyze.train_multiple_regression( training_no_show, training_show )

# puts lr_model.summary

# ======================   method 2
#
# feature_statistics_array = Analyze.train_odds_ratios( training_no_show, training_show )
#
#
# headers = feature_statistics_array[0].keys
#
# puts "Saving as --#{ stats_odds_ratios_filename }--"
# CSV.open("#{ stats_odds_ratios_filename }", "wb") do |csv|
#   csv << headers
#   feature_statistics_array.each do |items|
#     csv << items.values
#   end
# end
# #
# log_odds_ratios_by_feature_2 = Hash[
#   feature_statistics_array
#     .select {|e| e[:or_80_ci_lower] > 1 or e[:or_80_ci_upper] < 1}
#     .collect {|e| [e[:feature_name], e[:log_odds_ratio]] }
# ]
#

features = @encounters_all.collect {|e| e["features"].to_a}.flatten(1).group_by {|k,v| k}

unique_feature_names = features.keys 



def get_instances_from_encounters( encounters, feature_names)

  # create instances with relation name 'weather' and attributes
  instances = Weka::Core::Instances.new(relation_name: 'encounter').with_attributes do
    feature_names.each do |feature_name|
      nominal feature_name, values: [true, false]
    end
  
    # nominal :gender_male, values: [true, false]
    # nominal :no_show, values: [true, false]
    # numeric :temperature
    # numeric :humidity
    # nominal :windy, values: [true, false]
    # date    :last_storm, 'yyyy-MM-dd'
    # nominal :play, values: [:yes, :no], class_attribute: true
  end
  
  data = encounters.collect do |encounter|
    feature_names.collect {|feature_name| encounter["features"][feature_name] == 1 or encounter["features"][feature_name] == true}
  end

  instances.add_instances(data) # , weight: 2.0
  instances
end

puts "Assembling the training and test instances"
training_instances = get_instances_from_encounters( training_set, unique_feature_names)
training_instances.class_attribute = :no_show
training_instances.to_csv('encounters_training.csv')

test_instances = get_instances_from_encounters( test_set, unique_feature_names)
test_instances.class_attribute = :no_show

puts "  Done"

puts "Training the classifier"
classifier = Weka::Classifiers::Trees::RandomForest.new
# classifier.use_options('-I 200 -K 5')
classifier.train_with_instances(training_instances)
puts "  Done"


puts "Evaluating"
evaluation = classifier.evaluate(test_instances)
puts "  Done"
puts evaluation.summary


class_attr_i = unique_feature_names.index("no_show") #training_instances.class_attribute

# puts classifier.distribution_for(test_instances.first)
answers = test_instances.collect do |instance|
  [
    instance.values[class_attr_i] == "true", 
    classifier.classify(instance) == "true", 
    classifier.distribution_for(instance)["true"]
  ] # actual, estimated, pct
end

pct_no_show = 1.0 * answers.count {|e| e[0] } / answers.size

puts "% true positive: #{ 1.0 * answers.count {|e| e[0]  and e[1] } / answers.size }"
puts "% true negative: #{ 1.0 * answers.count {|e| !e[0] and !e[1] } / answers.size }"
puts "% false positive: #{ 1.0 * answers.count {|e| !e[0]  and e[1] } / answers.size }"
puts "% false negative: #{ 1.0 * answers.count {|e| e[0]  and !e[1] } / answers.size }"
puts "% actual no show: #{ pct_no_show }"
puts "% predicted as no show: #{ 1.0 * answers.count {|e| e[1] } / answers.size }"
puts "rms error (classified): #{ Math.sqrt(answers.collect {|e| ((e[0] ? 1.0 : 0.0) - (e[1] ? 1.0 : 0.0)) ** 2}.mean) }"
puts "rms error (probabilistic): #{ Math.sqrt(answers.collect {|e| ((e[0] ? 1.0 : 0.0) - e[2]) ** 2}.mean) }"
puts "rms error if constant prob used for all: #{ Math.sqrt(answers.collect {|e| ((e[0] ? 1.0 : 0.0) - pct_no_show) ** 2}.mean) } "
# =============================================================================
# ==============  assign each encounter a probability of no-show  =============

raise "hilo"
# rb=ReportBuilder.new
#
# puts "\nMethod: Baseline performance with a constant probability for all encounters"
# Analyze.assign_odds_ratios( @encounters_all, {}, :prob_no_show)
#
# Analyze.validate_model( test_no_show, test_show, :prob_no_show)
#
#
#
# puts "\nMethod: Multiple regression"
# Analyze.assign_multiple_regression( @encounters_all, lr_model, :prob_no_show)
#
# a=@encounters_all.collect {|e| e[:prob_no_show]}.to_vector
# rb.add(Statsample::Graph::Histogram.new(a))
#
# b=all_no_show.collect {|e| e[:prob_no_show]}.to_vector
# rb.add(Statsample::Graph::Histogram.new(b))
#
# Analyze.validate_model( test_no_show, test_show, :prob_no_show)
#
#
# puts "\nMethod: Simple odds ratios"
#
# Analyze.assign_odds_ratios( @encounters_all, log_odds_ratios_by_feature_2, :prob_no_show)
#
# a=@encounters_all.collect {|e| e[:prob_no_show]}.to_vector
# rb.add(Statsample::Graph::Histogram.new(a))
#
# a=all_no_show.collect {|e| e[:prob_no_show]}.to_vector
# rb.add(Statsample::Graph::Histogram.new(a))
#
# Analyze.validate_model( test_no_show, test_show, :prob_no_show)
#
#
#
#
# rb.save_html('histogram.html')


# =============================================================================
# =========================   validate the model   ============================
# squares = test_no_show.collect {|e| (1.0 - e[:prob_no_show]) ** 2 } +
#   test_show.collect {|e| (0.0 - e[:prob_no_show]) ** 2 }
#
# rms_error = Math.sqrt(squares.mean)
# puts "a validation was performed at RMS error of #{ rms_error }"

raise "x"
# threshold_of_no_show = 1 - 0.74 # greater than

# puts "with a threahold of #{ threshold_of_no_show }, the accuracy of prediction was #{ }"
step_size = 0.015

puts "Saving as --#{ validation_filename }--"
CSV.open("#{ validation_filename }", "wb") do |csv|
  csv << ["RMS error", rms_error]
  csv << ["P(predicted no show) lower range", "P(actual no show)", "n show", "n no show"]
  
  (0.0..0.8).step( 0.025 ).each do |prob| 
    n_no_show = @encounters_all.status_no_show.count {|e| ( prob...(prob + step_size) ).include? e[:prob_no_show] } 
    n_show = @encounters_all.status_completed.count {|e| ( prob...(prob + step_size) ).include? e[:prob_no_show] } 
    
    csv << [prob, 1.0 * n_no_show / ( n_no_show + n_show ), n_no_show, n_show]
  end
end  

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

# puts Reports.sessions(selected_entries, clinic_sessions)
def friendly_filename( input_string )
  input_string.gsub(/[^0-9A-Za-z.\-]+/, '_').downcase
end


def generate_and_save_sessions_report( provider, encounters, custom_filename = nil) #
  raise "no entries" if encounters.size == 0
  puts "Producing report..."
  clinic_sessions = Analyze.extract_clinic_sessions( encounters )
  
  friendly = friendly_filename( custom_filename || provider )
  filename_complete = "report_billing_#{friendly}_#{ Time.now.strftime("%F") }.txt"

  File.open(filename_complete , "w:UTF-8") do |file|
    file.write(Reports.sessions(encounters, clinic_sessions ).gsub("\n", "\r\n"))
  end
  puts "  Saved as #{ filename_complete }"
  
  filename_complete_2 = "report_prediction_#{friendly}_#{ Time.now.strftime("%F") }.txt"

  File.open(filename_complete_2 , "w:UTF-8") do |file|
    file.write(Reports.sessions_prediction(encounters, clinic_sessions ).gsub("\n", "\r\n"))
  end
  puts "  Saved as #{ filename_complete_2 }"
  
end


selected_entries = @encounters_all.select {|e| e["Provider"] == "PRICE, RAYMOND"}
  .select {|e| e["appt_at"] > DateTime.new(2016, 7, 1) and e["appt_at"] < DateTime.new(2017, 7, 1)}
  # .sort_by {|e| e["appt_at"]}

generate_and_save_sessions_report( "PRICE, RAYMOND", selected_entries)
generate_and_save_sessions_report( "many providers", @encounters_all
  .select {|e| e["appt_at"] > DateTime.new(2016, 7, 1) and e["appt_at"] < DateTime.new(2017, 7, 1)})

generate_and_save_sessions_report( "DO, DAVID", @encounters_all
.select {|e| e["Provider"] == "DO, DAVID"}
.select {|e| e["appt_at"] > DateTime.new(2016, 7, 1) and e["appt_at"] < DateTime.new(2017, 7, 1)})


# =============================================================================
# ==============================   output   ===================================


# =============================================================================
# ==============================   output   ===================================

headers = ["appt_at", "Provider", "Patient Name", "Visit Type", "Appt Status", :prob_no_show]

puts "Saving as --#{ prediction_output_filename }--"
CSV.open("#{ prediction_output_filename }", "wb") do |csv|
  csv << headers
  @encounters_all.each do |items| 
    csv << headers.collect {|header| items[header] }
  end
end  
