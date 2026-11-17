/* Shared online save settings. Leave SUPABASE_URL empty to turn sync off
   (the planner then saves only in the browser, as before).
   The anon key is safe to publish: Row Level Security limits the plan to
   its two members. Never put the service-role key here. */
window.SEATPLAN_CONFIG = {
  SUPABASE_URL: "",
  SUPABASE_ANON_KEY: "",
  PLAN_ID: "our-wedding"
};
