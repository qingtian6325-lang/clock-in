// Frontend config example
// For local preview: cp docs/config.example.js docs/config.js, then fill in
// On deploy: GitHub Actions generates config.js from Secrets automatically
// Note: the admin PIN lives only in the Supabase settings table, never here
window.APP_CONFIG = {
  SUPABASE_URL: "https://your-project.supabase.co",
  SUPABASE_ANON_KEY: "your anon key (public by design, used with RLS)",
  WORK_START: "09:00"
};
