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


# =============================================================================
# ===============================  parameters  ================================

timeslot_size = 15 # minutes
provider_grouping_filename = "provider_groupings.csv"
last_filename_root = input_root = "neurology_provider_visits_with_payer_20170608"
output_root = "report"

# =====================  Step 1 : Add calculated columns  =====================
# last_filename_root = Analyze.resave_with_prior_visit_counts( input_root )

# ====================  Step 2 : Modify columns like dates  ===================


# =====================  Step 3 : Filter rows of interest  ====================
# last_filename_root = Analyze.resave_if( lambda {|item, i, s|
   # [item].type_office_followup.loc_south_pav.any? }, last_filename_root, "sopa")

last_filename_root = Analyze.resave_if( lambda {|item, i, s|
      item["appt_at"] > DateTime.new(2016, 7, 1) and 
      item["appt_at"] < DateTime.new(2017, 8, 1)
   }, last_filename_root, "12mo")


         
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
# Pecularities of the data
# - sometimes there is identical patient in a slot twice, one cancelled, and one completed
# - Botox and EMG can sometimes have duplicate, triplicate, or even 4x of
#   same patient, same timeslot, same visit type, same status (completed)
#   DOE,JOHN EMG (Completed 15) / DOE,JOHN EMG (Completed 15)

# amongst completed encounters, eliminate the duplicate encounters associated 
# with Botox and EMG so we don't overcount minutes of patients seen
# 



# =============================================================================
# =======================  output a table of providers  =======================
#

headers = ["PROV_NAME", "N_ENCOUNTERS", "INCLUDE_IN_TRAINING_SET", "OUTPATIENT_DIVISION", "GENERATE_REPORT"]

if File.exists?( provider_grouping_filename ) 
   puts "Reading provider grouping file. "
   begin
      provider_groupings = CSV.read( provider_grouping_filename, headers: true )
      provider_groupings.each do |p|
         p["N_ENCOUNTERS"] = 0
      end
   rescue
      raise "  Provider grouping file -#{ provider_grouping_filename }- is invalid. Delete it and run again."
   end
else
   puts "Creating new provider grouping file"
   provider_groupings = []
end


headers = ["PROV_NAME", "N_ENCOUNTERS", "INCLUDE_IN_TRAINING_SET", "OUTPATIENT_DIVISION", "GENERATE_REPORT"]

provider_groupings_by_name = Hash[provider_groupings.collect {|e| [e["PROV_NAME"], e]}]

CSV.foreach( "#{ last_filename_root }.csv", headers: true) do |row|
   item = Hash[row]
   provider = item["Provider"]
   
   provider_groupings_by_name[provider] ||= {
      "PROV_NAME" => provider,
      "N_ENCOUNTERS" => 0
   }
   provider_groupings_by_name[provider]["N_ENCOUNTERS"] ||= 0
   provider_groupings_by_name[provider]["N_ENCOUNTERS"] += 1
end


CSV.open("#{ provider_grouping_filename }", "wb") do |csv|
  csv << headers
  provider_groupings_by_name.sort_by {|k,v| - (v["N_ENCOUNTERS"] || 0)}.each do |prov_name, e|
    csv << headers.collect {|header| e[header]}
  end
end
puts "  done"

provider_groupings = provider_groupings_by_name.values



# =============================================================================
# ==========================   generate reports   =============================
#
# puts Reports.sessions(selected_entries, clinic_sessions)



def generate_and_save_sessions_report( provider, encounters, custom_filename = nil, params={}) #
  raise "no entries" if encounters.size == 0
  puts "Producing report..."
  clinic_sessions = Analyze.extract_clinic_sessions( encounters )

  friendly = Reports.friendly_filename( custom_filename || provider )
  filename_complete = "report_billing_#{friendly}_#{ Time.now.strftime("%F") }.html"

  File.open(filename_complete , "w:UTF-8") do |file|
    file.write(Reports.session_efficiency(encounters, clinic_sessions, params).gsub("\n", "\r\n"))
  end
  puts "  Saved as #{ filename_complete }"

  filename_complete_2 = "report_sessions_#{friendly}_#{ Time.now.strftime("%F") }.html"

  File.open(filename_complete_2 , "w:UTF-8") do |file|
    file.write(Reports.session_details(clinic_sessions ).gsub("\n", "\r\n"))
  end
  puts "  Saved as #{ filename_complete_2 }"


end


#
# selected_entries = Analyze.load_if( lambda {|e| e["Provider"] == "DO, DAVID" and
#    e["appt_at"] > DateTime.new(2016, 7, 1) and
#    e["appt_at"] < DateTime.new(2017, 7, 1)}, last_filename_root)
#
# generate_and_save_sessions_report( "DO, DAVID", selected_entries)
# generate_and_save_sessions_report( "many providers", @encounters_all
#   .select {|e| e["appt_at"] > DateTime.new(2016, 7, 1) and e["appt_at"] < DateTime.new(2017, 7, 1)})
#
# generate_and_save_sessions_report( "DO, DAVID", @encounters_all
# .select {|e| e["Provider"] == "DO, DAVID"}
# .select {|e| e["appt_at"] > DateTime.new(2016, 7, 1) and e["appt_at"] < DateTime.new(2017, 7, 1)})



# generate individual reports
providers_for_individual_reports = provider_groupings.select {|e| e["GENERATE_REPORT"] == "TRUE"}
puts "Generating individual reports for #{ providers_for_individual_reports.collect {|e| e["PROV_NAME"]}.join(" / ")}"

# run in groups of 20 to not exceed memory limitations
providers_for_individual_reports.each_slice(20) do |providers|
   provider_names = providers.collect {|e| e["PROV_NAME"]}
   selected_entries_for_individual_reports = Analyze.load_if( lambda {|e| provider_names.include?(e["Provider"])  }, last_filename_root).group_by {|e| e["Provider"]}
   
   providers.each do |provider|
      puts "  Generating a report for individual #{ provider["PROV_NAME"] }"
      goal_hours_per_session = provider["OUTPATIENT_DIVISION"] == "Residents" ? 3 : 4
      
      if (selected_entries_for_individual_reports[provider["PROV_NAME"]] || []).any?
         generate_and_save_sessions_report( provider["PROV_NAME"], selected_entries_for_individual_reports[provider["PROV_NAME"]], nil, {goal_hours_per_session: goal_hours_per_session })
      else
         puts "Warning: #{ provider["PROV_NAME"] } has no entries"
      end
   end
end





# generate divisional reports

provider_groupings.group_by {|e| e["OUTPATIENT_DIVISION"] }.select {|k,v| k and k != ""}.each do |div_name, providers|
   provider_names = providers.collect {|e| e["PROV_NAME"]}

   puts "Generating a report for division #{ div_name }"

   selected_entries = Analyze.load_if( lambda {|e| provider_names.include?(e["Provider"]) }, last_filename_root)

   if selected_entries.any?
      generate_and_save_sessions_report( div_name, selected_entries, nil, {goal_hours_per_session: div_name == "Residents" ? 3 : 4})
   else
      puts "Warning: #{ provider_name } has no entries"
   end
end

