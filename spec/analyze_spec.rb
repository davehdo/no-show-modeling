# gem install rspec

require "./analyze.rb"

params = [
   {
      "color" => "blue", 
      "hue" => "bluish",
      "outcome" => "win",
      "outcome3" => "win",
   },
   {
      "color" => "white", 
      "outcome" => "win",
      "outcome3" => "win",
   },
   {
      "color" => "blue", 
      "hue" => "bluish",
      "outcome" => "lose",
      "outcome3" => "lose",
   },
   {
      "color" => "blue", 
      "hue" => "bluish",
      "outcome" => "win",
      "outcome3" => "win",
   },
   {
      "color" => "white", 
      "outcome" => "lose",
      "outcome3" => "tie",
   }
   
]

RSpec.describe Analyze, "#train_odds_ratios" do
   context "with valid params and binary outcome" do
      it "produces accurate odds ratio" do
         results = Analyze.train_odds_ratios( params, outcome: "outcome" )
         
         
         specific_result = results.select {|e| e[:feature_name]=="color=blue" and e[:outcome_0] == "win"}[0]
         # got: [{:feature_name=>"color=blue", :odds_ratio_outcome_0=>2.0, :outcome_0=>"win", :or_95_ci_lower=>0.0511...0=>3, :n_outcome_1=>2, :log_odds_ratio=>0.6931471805599453, :se_log_odds_ratio=>1.8708286933869707}]
         
         expect( specific_result).to_not eq(nil)
         expect( specific_result[:outcome_0] ).to eq( "win" ) 
         expect( specific_result[:odds_ratio_outcome_0] ).to eq( 2.0 )
      end
      
      it "produces accurate odds ratio for a sparsely encoded param" do
         results = Analyze.train_odds_ratios( params, outcome: "outcome" )
         
         
         specific_result = results.select {|e| e[:feature_name]=="hue=bluish" and e[:outcome_0] == "win"}[0]
         
         expect( specific_result).to_not eq(nil)
         expect( specific_result[:outcome_0] ).to eq( "win" )         
         expect( specific_result[:odds_ratio_outcome_0] ).to eq( 2.0 )
      end

      # it "produces accurate odds ratio for a sparsely encoded param" do
      #    results = Analyze.train_odds_ratios( params, outcome: "outcome" )
      #
      #    specific_result = results.collect {|e| e[:feature_name] }.select {|e| e =~ /hue=/}.uniq
      #
      #    expect( specific_result ).to eq( ["hue=bluish", "hue=nil"] )
      # end
      
   end
   
   context "with valid params and multiple outcome possibilities" do
      it "produces accurate odds ratio" do
         results = Analyze.train_odds_ratios( params, outcome: "outcome3" )
         
         specific_result = results.select {|e| e[:feature_name]=="color=blue" and e[:outcome_0] == "win"}[0]
         # got: [{:feature_name=>"color=blue", :odds_ratio_outcome_0=>2.0, :outcome_0=>"win", :or_95_ci_lower=>0.0511...0=>3, :n_outcome_1=>2, :log_odds_ratio=>0.6931471805599453, :se_log_odds_ratio=>1.8708286933869707}]
         
         expect( specific_result).to_not eq(nil)
         
         expect( specific_result[:outcome_0] ).to eq( "win" ) 
         expect( specific_result[:odds_ratio_outcome_0] ).to eq( 2.0 )
      end
      
      it "produces accurate odds ratio for a sparsely encoded param" do
         results = Analyze.train_odds_ratios( params, outcome: "outcome3" )
         
         specific_result = results.select {|e| e[:feature_name]=="hue=bluish" and e[:outcome_0] == "win"}[0]
         
         expect( specific_result).to_not eq(nil)
         
         expect( specific_result[:outcome_0] ).to eq( "win" )         
         expect( specific_result[:odds_ratio_outcome_0] ).to eq( 2.0 )
      end
      
      it "produces accurate odds ratio for a sparsely encoded param" do
         results = Analyze.train_odds_ratios( params, outcome: "outcome3" )
         
         specific_result = results.select {|e| e[:feature_name]=="color=white" and e[:outcome_0] == "tie"}[0]
         
         expect( specific_result).to_not eq(nil)
         expect( specific_result[:outcome_0] ).to eq( "tie" )         
         expect( specific_result[:odds_ratio_outcome_0] ).to eq( 1.0 / 0 )
      end
      
   end
   
end