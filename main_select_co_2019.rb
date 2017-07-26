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

# https://github.com/paulgoetze/weka-jruby/wiki


# =============================================================================
# ===============================  parameters  ================================
last_filename_root = input_root = "neurology_provider_visits_with_payer_20170608"

provider_names = [
   "O'KULA, SUSANNA S",
   "ARADI, STEPHEN D",
   "CHERAYIL, NEENA R",
   "MATTIS, JOANNA HOCHBERG",
   "AAMODT, WHITLEY WARFIELD",
   "TIZAZU, ETSEGENET",
   "CONRAD, ERIN C",
   "GANGULY, TANEETA M",
   "MANNING, SARA",
   "ROSENBERG, JON",
   "ZHOU, XIN"
]

# ======================  Step 1 : keep only follow ups  ======================
# last_filename_root = Analyze.resave_with_prior_visit_counts( input_root )

last_filename_root = Analyze.resave_if( lambda {|item, i, s| 
      provider_names.include? item["Provider"]
   }, last_filename_root, "co2019")

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

last_filename_root = Analyze.resave_without_columns( last_filename_root, "phisafe", mask: ["MRN", "Referring Provider"], omit: ["CSN", "Patient Name"])
