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
output_root = "features"

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

training_fraction = 1
training_features, test_features = Analyze.extract_training_and_test_features_from_file(last_filename_root, training_fraction )


puts "Getting prototype features"
features_hash = (training_features + test_features).collect {|e| e.to_a}
   .flatten(1).uniq.group_by {|k,v| k}.collect do |feature_name, all_values|
      unique_values =  all_values.collect {|k,v| v}.uniq
   
      [feature_name, unique_values]
end


y_features = features_hash.select {|k,v| k == "zip_code" }
x_features = features_hash - y_features


puts "Counting"
counts_by_feature_value = {}

training_features.each_with_index do |row, i|
   # j = options.index(row["outcome"])
   y_features.each do |y_f, y_vals|
      x_features.each do |x_f, x_vals|
         puts "  #{x_f}=#{row[x_f]}&#{y_f}=#{row[y_f]}" if i == 0
         counts_by_feature_value["#{x_f}=#{row[x_f]}&#{y_f}=#{row[y_f]}"] ||= 0
         counts_by_feature_value["#{x_f}=#{row[x_f]}&#{y_f}=#{row[y_f]}"] += 1
      end
   end
   puts "  #{i}" if i % 5000 == 0
end

y_kv_pairs = y_features.collect {|y_f, y_vals| y_vals.collect {|y_v| "#{y_f}=#{y_v}"}}.flatten
x_kv_pairs = x_features.collect {|x_f, x_vals| x_vals.collect {|x_v| "#{x_f}=#{x_v}"}}.flatten

output_filename = "#{ output_root }_breakdown_by_zip.csv"
puts "Saving to file #{output_filename}"

CSV.open(output_filename, "wb") do |csv_out|

   csv_out << ["feature"] + x_kv_pairs
      
   y_kv_pairs.each do |y_kv|
      csv_out << [y_kv] + x_kv_pairs.collect do |x_kv|
         counts_by_feature_value["#{x_kv}&#{y_kv}"] || 0
      end
   end

   # features_hash.each do |feature_name, value_names|
   #    value_names.each do |v|
   #       counts_by_feature_value["#{feature_name}=#{v}"] ||= [0, 0]
   #
   #       csv_out << [ "#{feature_name}=#{v}", feature_name, v] + counts_by_feature_value["#{feature_name}=#{v}"]
   #    end
   # end
end


# =============================================================================
# ========================   assembling into instances   ======================

puts "done"
