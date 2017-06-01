# this script analyzes billing reports
# Report is calling “Charges, Payments and Adjustments”
# exported from business objects… (PROMIS)


require "csv"
require "./filters.rb"
require "./reports.rb"
require "./analyze.rb"
# require 'yaml'

# =============================================================================
# ===============================  parameters  ================================
input_file = "neurologyvisitsjuly2014-november2017.csv"
timeslot_size = 15 # minutes
stats_odds_ratios_filename = "stats_odds_ratios.csv"
stats_odds_ratios_significant_filename = "stats_odds_ratios_significant.csv"
provider_grouping_template_filename = "provider_groupings_template.csv"
prediction_output_filename = "no_show_predictions.csv"


# =============================================================================
# ============================   load data file   =============================

puts "Loading data file #{ input_file }"
@encounters_all = CSV.read(input_file, {headers: true})
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

  
# =============================================================================
# =========   fix timestamps and extract features for each encounter  =========

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
  
  # features
  zip = e["Zip Code"] ? e["Zip Code"][0..4].rjust(5, "0") : "absent"
  dist = distance_by_zip[ zip ]   # distance from hosp

  # we do a sparse encoding -- anything not listed in features is assumed to be 0
  e["features"] = {
   "zip_#{ zip }" => 1,
   "dist_#{ dist ? (2 ** Math.log(dist + 0.001, 2).round).to_f.round.to_s.rjust(4, "0") : "unknown"}_km" => 1,
   "age_decade_#{ (e["Age at Encounter"].to_i / 10.0).round }" => 1, 
   "gender_#{ e["Gender"].downcase }" => 1,
   "appt_hour_#{ e["appt_at"].hour.to_s.rjust(2, "0") }" => 1,
   "appt_made_#{ e["appt_booked_on"] ? (2 ** Math.log((e["appt_at"] - e["appt_booked_on"] + 1).to_f, 2).round).to_s.rjust(3, "0") : "unknown_" }d_advance" => 1,
   "appt_type_#{ e["Visit Type"].downcase }" => 1,
   "dept_#{ e["Department"].downcase.gsub(" ", "_") }" => 1
  }
  
  puts "Warning: #{ e["Appt. Length"] } min appt but #{ e["timeslots"].size } timeslots (#{e["timeslots"]})" if (1.0 * e["Appt. Length"].to_i / timeslot_size).to_i != e["timeslots"].size
}


# =============================================================================
# ===========================   features analysis   ===========================
# =====================  and calculation of odds ratios  ======================
feature_statistics_array = Analyze.generate_odds_ratios_for_each_feature(@encounters_all.status_no_show, @encounters_all.status_completed)



headers = feature_statistics_array[0].keys

puts "Saving as --#{ stats_odds_ratios_filename }--"
CSV.open("#{ stats_odds_ratios_filename }", "wb") do |csv|
  csv << headers
  feature_statistics_array.each do |items| 
    csv << items.values
  end
end  

significant_feature_statistics_array = feature_statistics_array.select {|e| e[:or_80_ci_lower] > 1 or e[:or_80_ci_upper] < 1}
log_odds_ratios_by_feature = Hash[significant_feature_statistics_array.collect {|e| [e[:feature_name], e[:log_odds_ratio]] }]


# =============================================================================
# ==============  assign each encounter a probability of no-show  =============
@encounters_all.each {|e| 
  e[:log_odds_ratios_itemized] = e["features"].collect {|k,v|
    [k, log_odds_ratios_by_feature[k]]
  }
  
  sum_log_odds = e[:log_odds_ratios_itemized].collect {|f| f[1]}.compact.sum
  e[:odds_ratio_no_show] = Math.exp( sum_log_odds )
  pretest_odds = 0.1 / 0.9
  posttest_odds = e[:odds_ratio_no_show] * pretest_odds 
  e[:prob_no_show] = posttest_odds / (1 + posttest_odds)
}





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

def generate_and_save_sessions_report( provider, encounters, custom_filename = nil) #
  raise "no entries" if encounters.size == 0
  puts "Producing report..."
  # ==========================  generate a filename  ==========================
  if custom_filename
    provider_name_filesystem_friendly = custom_filename.gsub(/[^0-9A-Za-z.\-]+/, '_').downcase
    filename_complete = "report_billing_#{provider_name_filesystem_friendly}_#{ Time.now.strftime("%F") }.txt"
  else
    provider_name_filesystem_friendly = provider.gsub(/[^0-9A-Za-z.\-]+/, '_').downcase
    filename_complete = "report_billing_#{provider_name_filesystem_friendly}_#{ Time.now.strftime("%F") }.txt"
  end

  clinic_sessions = Analyze.extract_clinic_sessions( encounters )
  
  File.open(filename_complete , "w:UTF-8") do |file|
    file.write(Reports.sessions(encounters, clinic_sessions ).gsub("\n", "\r\n"))
  end
  puts "  Saved as #{ filename_complete }"

end


selected_entries = @encounters_all.select {|e| e["Provider"] == "PRICE, RAYMOND"}
  .select {|e| e["appt_at"] > DateTime.new(2016, 7, 1) and e["appt_at"] < DateTime.new(2017, 7, 1)}
  # .sort_by {|e| e["appt_at"]}

generate_and_save_sessions_report( "PRICE, RAYMOND", selected_entries)
generate_and_save_sessions_report( "many providers", @encounters_all
  .select {|e| e["appt_at"] > DateTime.new(2016, 7, 1) and e["appt_at"] < DateTime.new(2017, 7, 1)})

generate_and_save_sessions_report( "CHEN, MARIA FANG-CHUN", @encounters_all
.select {|e| e["Provider"] == "CHEN, MARIA FANG-CHUN"}
.select {|e| e["appt_at"] > DateTime.new(2016, 7, 1) and e["appt_at"] < DateTime.new(2017, 7, 1)})


# =============================================================================
# ==============================   output   ===================================


clinic_sessions = Analyze.extract_clinic_sessions( selected_entries )

clinic_sessions.each do |clinic_session|
    puts "=== #{ clinic_session[:id] } / #{ clinic_session[:encounters].status_completed.sum_minutes } / #{ clinic_session[:hours_booked]} hb / #{ clinic_session[:visual] } / #{ (clinic_session[:visual].count(".") + clinic_session[:visual].count("X")) * 0.25}"

    clinic_session[:encounters].group_by {|e| e["appt_at"].strftime("%H:%M") }.each do |time, entries_for_time|
      entries_text = entries_for_time.collect {|e| "#{ e["Patient Name"]} #{ e["Visit Type"]} (#{ e["Appt Status"]} #{e["Appt. Length"]}) #{ e[:prob_no_show]}" }.join(" / ")
      puts "    #{ time }  #{ entries_text } "
    end

end

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
