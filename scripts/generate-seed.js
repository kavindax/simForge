const fs = require('fs');
const path = require('path');

// Presets are maintained in supabase/seed_presets.sql
// Regenerate by editing that file directly, or restore CATALOGUE in index.html temporarily.
const seedPath = path.join(__dirname, '../supabase/seed_presets.sql');
if (!fs.existsSync(seedPath)) {
  console.error('seed_presets.sql not found');
  process.exit(1);
}
console.log('Presets are in supabase/seed_presets.sql — run it in Supabase SQL Editor after schema.sql');
