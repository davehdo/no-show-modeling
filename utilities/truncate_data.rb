require "csv"
require "./filters.rb"
# create a subset of a data file for faster development and testing

# # =============================================================================
# # ===============================  parameters  ================================
root = "neurology_provider_visits_with_payer_20170608"
n_to_keep = 1000


input_file = "#{ root }.csv"
output_file = "#{ root }_truncated_#{ n_to_keep }.csv"



# =============================================================================
# ============================   load data file   =============================

puts "Loading data file #{ input_file }"
content = File.read(input_file)

# if we use new instead of read, it doesn't parse, which is a very computationally expensive function

@encounters_all = CSV.new(content, headers: true)
# @encounters_all = CSV.read(input_file, {headers: true})

# puts "  There are #{ @encounters_all.size } records"
headers = @encounters_all.first.collect {|a,b| a}


n_saved = 0

CSV.open("#{ output_file }", "wb") do |csv_out|
  csv_out << headers

  while (row = @encounters_all.shift) and n_saved < n_to_keep
    item = Hash[row]
    # raise item.inspect
    if [item].type_office_followup.any?
      csv_out << row.collect {|a,b| b} 
      n_saved += 1
      puts "Saved #{n_saved}" if n_saved % 100 == 0
    end
  end

end


puts "Saved #{ n_saved } records into #{ output_file}"
