require "csv"
require "./filters.rb"
# this will run faster on ruby than jruby

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

@encounters_all = CSV.new(content, headers: true)
# @encounters_all = CSV.read(input_file, {headers: true})

# puts "  There are #{ @encounters_all.size } records"
headers = Hash[@encounters_all.first].keys


n_saved = 0

CSV.open("#{ output_file }", "wb") do |csv_out|
  csv_out << headers

  while (row = @encounters_all.shift) and n_saved < n_to_keep
    item = Hash[row]
    # raise item.inspect
    if [item].type_office_followup.any?
      csv_out << item.values 
      n_saved += 1
      puts "n_saved #{n_saved}"
    end
  end

end


# puts "Saving #{@encounters_all.size} records into #{ output_file}"
