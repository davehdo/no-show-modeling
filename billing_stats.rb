class BillingStats
  require "./filters.rb"

  def self.outpatient_stats( billings_for_division )
    n_outpt_followups = billings_for_division.outpatient_follow.sum_quantity
    n_outpt_encounters = billings_for_division.outpatient.sum_quantity
    n_outpt_new = billings_for_division.outpatient_new.sum_quantity
    n_outpt_consult = billings_for_division.outpatient_consult.sum_quantity
    outpt_initial = billings_for_division.outpatient_new + billings_for_division.outpatient_consult
    n_outpt_initial = outpt_initial.sum_quantity
    n_outpt_init_l3 = outpt_initial.level_3.sum_quantity 
    n_outpt_init_l4 = outpt_initial.level_4.sum_quantity
    n_outpt_init_l5 = outpt_initial.level_5.sum_quantity

    n_outpt_followup_l3 = (billings_for_division.outpatient_follow).level_3.sum_quantity 
    n_outpt_followup_l4 = (billings_for_division.outpatient_follow).level_4.sum_quantity
    n_outpt_followup_l5 = (billings_for_division.outpatient_follow).level_5.sum_quantity
  
    outpt = billings_for_division.outpatient
    n_outpt = billings_for_division.outpatient.sum_quantity 
    n_outpt_l3 = outpt.level_3.sum_quantity 
    n_outpt_l4 = outpt.level_4.sum_quantity
    n_outpt_l5 = outpt.level_5.sum_quantity

    {
      outpt_frac_encounters_that_are_initial: proportion_stats( n_outpt_encounters -n_outpt_followups, n_outpt_encounters ),
      outpt_frac_initial_that_are_consult: proportion_stats( n_outpt_consult, n_outpt_consult + n_outpt_new ),
      outpt_frac_initial_level_3_and_up: proportion_stats( n_outpt_init_l3 + n_outpt_init_l4 + n_outpt_init_l5, n_outpt_initial),
      outpt_frac_initial_level_4_and_up: proportion_stats( n_outpt_init_l4 + n_outpt_init_l5, n_outpt_initial),
      outpt_frac_initial_level_5: proportion_stats( n_outpt_init_l5, n_outpt_initial),
      outpt_frac_followup_level_3_and_up: proportion_stats(n_outpt_followup_l3 + n_outpt_followup_l4 + n_outpt_followup_l5, n_outpt_followups),
      outpt_frac_followup_level_4_and_up: proportion_stats(n_outpt_followup_l4 + n_outpt_followup_l5, n_outpt_followups),
      outpt_frac_followup_level_5: proportion_stats(n_outpt_followup_l5, n_outpt_followups),
      outpt_frac_level_3_and_up: proportion_stats(n_outpt_l3 + n_outpt_l4 + n_outpt_l5, n_outpt),
      outpt_frac_level_4_and_up: proportion_stats(n_outpt_l4 + n_outpt_l5, n_outpt),
      outpt_frac_level_5: proportion_stats(n_outpt_l5, n_outpt),
    }

  end

  def self.inpatient_stats( billings_for_division )
    inpt = billings_for_division.inpatient
    n_inpt = inpt.sum_quantity
    n_inpt_l3 = inpt.level_3.sum_quantity 
    n_inpt_l4 = inpt.level_4.sum_quantity
    n_inpt_l5 = inpt.level_5.sum_quantity

    inpt_new = billings_for_division.inpatient_new
    n_inpt_new = inpt_new.sum_quantity
    n_inpt_new_l1 = inpt_new.level_1.sum_quantity 
    n_inpt_new_l2 = inpt_new.level_2.sum_quantity
    n_inpt_new_l3 = inpt_new.level_3.sum_quantity
  
    inpt_consult = billings_for_division.inpatient_consult
    n_inpt_consult = inpt_consult.sum_quantity
    n_inpt_consult_l3 = inpt_consult.level_3.sum_quantity 
    n_inpt_consult_l4 = inpt_consult.level_4.sum_quantity
    n_inpt_consult_l5 = inpt_consult.level_5.sum_quantity
  
    inpt_initial_ed = billings_for_division.inpatient_initial_ed
    n_inpt_initial_ed = inpt_initial_ed.sum_quantity
    n_inpt_initial_ed_l3 = inpt_initial_ed.level_3.sum_quantity 
    n_inpt_initial_ed_l4 = inpt_initial_ed.level_4.sum_quantity
    n_inpt_initial_ed_l5 = inpt_initial_ed.level_5.sum_quantity
  
    inpt_initial_obs = billings_for_division.inpatient_initial_obs
    n_inpt_initial_obs = inpt_initial_obs.sum_quantity
    n_inpt_initial_obs_l3 = inpt_initial_obs.level_3.sum_quantity 
    n_inpt_initial_obs_l4 = inpt_initial_obs.level_4.sum_quantity
    n_inpt_initial_obs_l5 = inpt_initial_obs.level_5.sum_quantity
  
    inpt_followup = billings_for_division.inpatient_followup
    n_inpt_followup = inpt_followup.sum_quantity
    n_inpt_followup_l3 = inpt_followup.level_3.sum_quantity 
    n_inpt_followup_l4 = inpt_followup.level_4.sum_quantity  # level 4 and 5 don't exist for inpatient
    n_inpt_followup_l5 = inpt_followup.level_5.sum_quantity  # level 4 and 5 don't exist for inpatient
  
    {
      inpt_frac_level_3_and_up: proportion_stats(n_inpt_l3 + n_inpt_l4 + n_inpt_l5, n_inpt),
      inpt_frac_level_4_and_up: proportion_stats(n_inpt_l4 + n_inpt_l5, n_inpt),
      inpt_frac_level_5: proportion_stats(n_inpt_l5, n_inpt),
      inpt_frac_consult_level_3_and_up: proportion_stats(n_inpt_consult_l3 + n_inpt_consult_l4 + n_inpt_consult_l5, n_inpt_consult),
      inpt_frac_consult_level_4_and_up: proportion_stats(n_inpt_consult_l4 + n_inpt_consult_l5, n_inpt_consult),
      inpt_frac_consult_level_5: proportion_stats(n_inpt_consult_l5, n_inpt_consult),
      inpt_frac_initial_ed_level_3_and_up: proportion_stats(n_inpt_initial_ed_l3 + n_inpt_initial_ed_l4 + n_inpt_initial_ed_l5, n_inpt_initial_ed),
      inpt_frac_initial_ed_level_4_and_up: proportion_stats(n_inpt_initial_ed_l4 + n_inpt_initial_ed_l5, n_inpt_initial_ed),
      inpt_frac_initial_ed_level_5: proportion_stats(n_inpt_initial_ed_l5, n_inpt_initial_ed),
      inpt_frac_initial_obs_level_3_and_up: proportion_stats(n_inpt_initial_obs_l3 + n_inpt_initial_obs_l4 + n_inpt_initial_obs_l5, n_inpt_initial_obs),
      inpt_frac_initial_obs_level_4_and_up: proportion_stats(n_inpt_initial_obs_l4 + n_inpt_initial_obs_l5, n_inpt_initial_obs),
      inpt_frac_initial_obs_level_5: proportion_stats(n_inpt_initial_obs_l5, n_inpt_initial_obs),
      inpt_frac_new_level_1_and_up: proportion_stats(n_inpt_new_l1 + n_inpt_new_l2 + n_inpt_new_l3, n_inpt_new),
      inpt_frac_new_level_2_and_up: proportion_stats(n_inpt_new_l2 + n_inpt_new_l3, n_inpt_new),
      inpt_frac_new_level_3: proportion_stats(n_inpt_new_l3, n_inpt_new),
      inpt_frac_followup_level_3_and_up: proportion_stats( (n_inpt_followup_l3 + n_inpt_followup_l4 + n_inpt_followup_l5), n_inpt_followup),    
    }

  end
end