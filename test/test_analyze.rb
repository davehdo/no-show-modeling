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
require "./analyze.rb"
# require 'statsample' # if cannot find statssample; run gem install statsample



# =============================================================================
# create a test csv file
output_file = "test_data"

headers = ["row", "const", "rand"]
CSV.open("#{ output_file }.csv", "wb") do |csv_out|
  csv_out << headers
  (1..20).each do |n|
    csv_out << [n, 1, rand]
    csv_out << [n, 1, rand]
  end
  
  (1..20).each do |n|
    csv_out << [n, 1, rand]
    csv_out << [n, 1, rand]
  end
  
end


# =========================  Step 2 : eliminate dup  ==========================
# amongst completed encounters, eliminate the duplicate encounters associated 
# with Botox and EMG so we don't overcount minutes of patients seen
Analyze.resave_without_dup( "#{ output_file }", "dup", lambda {|e| e["row"]})

# =======================  Step 3 : truncate for now  =========================




