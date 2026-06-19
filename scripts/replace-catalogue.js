const fs = require('fs');
const path = require('path');

const p = path.join(__dirname, '../index.html');
let html = fs.readFileSync(p, 'utf8');
const start = html.indexOf('// SIMULATION CATALOGUE');
const end = html.indexOf('// CUSTOM LIBRARY (localStorage)');
if (start < 0 || end < 0) {
  console.error('markers not found', start, end);
  process.exit(1);
}

const replacement = `// CATEGORY METADATA + PRESET LOADING (from Supabase)
// ═══════════════════════════════════════════════════════
const CATEGORIES = {
  physics: { label: 'Physics', icon: '⚛️', color: '#4a9eff' },
  chemistry: { label: 'Chemistry', icon: '⚗️', color: '#3ecf8e' },
  biology: { label: 'Biology', icon: '🧬', color: '#ff6b6b' },
  mathematics: { label: 'Mathematics', icon: '📐', color: '#f5a623' },
  custom: { label: 'My Simulations', icon: '📁', color: '#cc5de8' }
};

let presetCatalogue = {};
let presetsLoaded = false;

function getCategory(catKey) {
  return CATEGORIES[catKey] || CATEGORIES.custom;
}

function dbRowToSim(row) {
  return {
    name: row.name,
    icon: row.icon || '🔬',
    desc: row.description || '',
    concepts: row.concepts || [],
    objectives: row.objectives || [],
    params: row.param_docs || [],
    code: row.code || '',
    slug: row.slug,
    presetKey: row.preset_key,
    isPreset: true,
    isCustom: false
  };
}

async function loadPresets() {
  if (presetsLoaded) return presetCatalogue;
  try {
    const { data, error } = await supabaseClient
      .from('simulations')
      .select('*')
      .eq('is_preset', true)
      .order('name');
    if (error) throw error;
    presetCatalogue = {};
    (data || []).forEach(row => {
      const cat = row.category || 'custom';
      if (!presetCatalogue[cat]) presetCatalogue[cat] = {};
      presetCatalogue[cat][row.preset_key] = dbRowToSim(row);
    });
  } catch (e) {
    console.warn('Failed to load presets:', e.message);
    presetCatalogue = {};
  }
  presetsLoaded = true;
  return presetCatalogue;
}

function findPreset(presetKey) {
  for (const [catKey, sims] of Object.entries(presetCatalogue)) {
    if (sims[presetKey]) return { catKey, simKey: presetKey, sim: sims[presetKey] };
  }
  return null;
}

// ═══════════════════════════════════════════════════════
`;

html = html.slice(0, start) + replacement + html.slice(end);
fs.writeFileSync(p, html);
console.log('Replaced CATALOGUE block');
