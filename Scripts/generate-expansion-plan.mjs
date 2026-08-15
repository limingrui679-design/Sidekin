#!/usr/bin/env node

import fs from "node:fs/promises";
import path from "node:path";
import process from "node:process";

const projectRoot = process.cwd();
const outputRoot = path.join(projectRoot, "ArtSources", "Expansion200");

// These are morphological and art-direction seeds, not product categories.
// The shipped catalog exposes free-form tags and one continuous lineage grid.
const rows = [
  ["astral-vowkeeper", "Astral Vowkeeper", "nonhuman humanoid", "faceless four-armed celestial knight", "split comet helm, four arms, crescent lance, and diamond chest aperture", "moonsteel plates and sapphire crystal", "orbiting vow-runes", "sacred", "poised", "ritual-strides", "#55E8FF", "#835BFF"],
  ["moonveil-oracle", "Moonveil Oracle", "nonhuman humanoid", "owl-masked floating oracle", "wide owl mask, draped crescent sleeves, three ribbon tails, and a moon disc", "pearl ceramic and midnight silk", "silver dream motes", "mysterious", "spectral", "hovering-glides", "#BBD7FF", "#7057D9"],
  ["prism-antler-warden", "Prism Antler Warden", "nonhuman humanoid", "crystal stag sentinel", "branching prism antlers, digitigrade legs, broad shield forearm, and narrow deer mask", "faceted crystal and pale armor", "refracted rainbow wards", "exquisite", "poised", "measured-digitigrade-steps", "#85F3FF", "#D95CFF"],
  ["tide-song-magus", "Tide-Song Magus", "nonhuman humanoid", "nautilus-headed tide mage", "spiral shell head, two finned arms, trailing mantle, and tuning-fork staff", "mother-of-pearl shell and wet bronze", "cyan resonance rings", "elegant", "flowing", "spiral-swims-and-hovering", "#52E4E8", "#C7A3FF"],
  ["inkshadow-dancer", "Inkshadow Dancer", "nonhuman humanoid", "living-ink masked dancer", "white brush mask, ribbon limbs, split calligraphy cloak, and fan-shaped hands", "liquid black ink and rice-paper highlights", "violet brushfire", "mysterious", "agile", "ribbon-spins", "#EDE7FF", "#7C3AED"],
  ["ivory-bell-paladin", "Ivory Bell Paladin", "nonhuman humanoid", "porcelain bell golem knight", "bell-shaped torso, arched shoulder handles, stout legs, and hammer clapper", "crackled ivory porcelain and antique gold", "warm harmonic halos", "sacred", "heavy", "measured-bell-steps", "#FFF1C9", "#E5A63B"],
  ["scarab-sun-priest", "Scarab Sun Priest", "nonhuman humanoid", "beetle-faced solar priest", "scarab mask, four folded wing panels, staff arms, and radiant abdomen", "lapis carapace and chased gold", "sun-disc glyphs", "regal", "poised", "ceremonial-marches", "#FFD34E", "#265BCE"],
  ["storm-mask-runner", "Storm-Mask Runner", "nonhuman humanoid", "faceless cloud courier", "lightning mask, runner legs, wind-sock scarf, and two turbine calves", "stormglass and flexible white armor", "electric-blue slipstream", "heroic", "agile", "thunder-sprints", "#79E7FF", "#5367FF"],
  ["aurora-fox-envoy", "Aurora Fox Envoy", "nonhuman humanoid", "bipedal fox spirit envoy", "long fox mask, two upright ears, fan tail, and aurora sleeve fins", "opal fur plates and translucent silk", "polar-light ribbons", "elegant", "buoyant", "light-footed-leaps", "#72F7D5", "#B15CFF"],
  ["obsidian-lion-champion", "Obsidian Lion Champion", "nonhuman humanoid", "volcanic lion arena champion", "lion mask, massive gauntlets, digitigrade feet, and circular ember mane", "obsidian armor and molten brass", "solar flame arcs", "fierce", "heavy", "arena-charges", "#FF7A32", "#1B1B29"],
  ["clockwork-harlequin", "Clockwork Harlequin", "nonhuman humanoid", "mechanical jester construct", "split crescent mask, spring limbs, diamond torso, and twin ribbon blades", "enameled clockwork and polished brass", "tick-tock neon sparks", "playful", "bouncing", "springing-cartwheels", "#FF5DC8", "#56E5FF"],
  ["void-moth-seer", "Void Moth Seer", "nonhuman humanoid", "moth-headed cosmic seer", "wide antennae, four patterned wings, slim robed body, and eye-shaped lantern", "velvet chitin and starlit membrane", "indigo omen dust", "mysterious", "winged", "silent-fluttering", "#7D67FF", "#E8B8FF"],
  ["lotus-crown-sage", "Lotus Crown Sage", "nonhuman humanoid", "porcelain lotus spirit", "petal crown, smooth mask face, floating prayer hands, and seated bud skirt", "white porcelain and amethyst crystal", "lavender serenity rings", "sacred", "buoyant", "meditative-hovering", "#F5ECFF", "#9D73FF"],
  ["rune-coral-warden", "Rune Coral Warden", "nonhuman humanoid", "coral-armored reef guardian", "branching coral helm, pincer gauntlet, finned calves, and rune shield", "blue coral stone and pearl shell", "aquamarine ward currents", "ancient", "heavy", "tidal-strides", "#38DCC9", "#3A6EDD"],
  ["dreamglass-fencer", "Dreamglass Fencer", "nonhuman humanoid", "faceless glass duelist", "teardrop mask, needle rapier arm, long coat shards, and crescent heels", "smoked dreamglass and silver wire", "rose-violet afterimages", "exquisite", "agile", "weightless-lunges", "#E9B5FF", "#6E72FF"],
  ["thunder-komainu-guard", "Thunder Komainu Guard", "nonhuman humanoid", "lion-dog temple guardian", "komainu muzzle, cloud mane, armored bipedal stance, and thunder drum shield", "blue stone hide and gold armor", "white lightning knots", "sacred", "heavy", "guardian-stomps", "#69BFFF", "#FFD768"],
  ["silk-comet-monk", "Silk Comet Monk", "nonhuman humanoid", "faceless comet-silk monk", "smooth comet mask, elongated sleeves, orbit sash, and three floating palms", "luminous silk and meteor iron", "golden comet script", "serene", "flowing", "circular-martial-glides", "#F8D670", "#6C7BFF"],
  ["eclipse-puppeteer", "Eclipse Puppeteer", "nonhuman humanoid", "marionette eclipse spirit", "crescent faceplate, jointed limbs, suspended control halo, and four thread fingers", "black lacquer and moon-silver joints", "red eclipse strings", "dark", "spectral", "suspended-puppet-steps", "#FF4F75", "#5A46A8"],
  ["nebula-smith", "Nebula Smith", "nonhuman humanoid", "starforge golem artisan", "anvil torso, furnace visor, asymmetric hammer arms, and comet apron", "dark star-metal and cobalt crystal", "miniature nebula flames", "heroic", "heavy", "forge-stomps", "#4CB9FF", "#FF8E43"],
  ["frosthorn-sentinel", "Frosthorn Sentinel", "nonhuman humanoid", "blue horned guardian beast", "single swept ice horn, masked feline face, plated shoulders, and halberd tail", "glacier crystal and navy armor", "frost-blue sigils", "regal", "poised", "guarding-pivots", "#82E7FF", "#4966DD"],
  ["ember-mask-shaman", "Ember-Mask Shaman", "nonhuman humanoid", "charcoal idol shaman", "carved ember mask, four short arms, featherless flame mantle, and forked staff tail", "charcoal woodstone and copper", "smokeless orange spirit fire", "ancient", "spectral", "ritual-hops", "#FF8C3A", "#61304C"],
  ["lunar-kitsune-archon", "Lunar Kitsune Archon", "nonhuman humanoid", "nine-tail moon fox archon", "fox mask, tall digitigrade stance, nine crescent tails, and ring-blade sleeves", "pearl fur armor and moon glass", "silver-blue foxfire", "sacred", "poised", "moonlit-dance-steps", "#DDEBFF", "#7788FF"],
  ["deepsea-lantern-knight", "Deepsea Lantern Knight", "nonhuman humanoid", "anglerfish-headed abyss knight", "lure lantern, armored fish skull, anchor blade, and fin cloak", "black pressure shell and aged copper", "teal bioluminescence", "mysterious", "heavy", "pressure-lunges", "#20D6C7", "#26326A"],
  ["copper-crow-artificer", "Copper Crow Artificer", "nonhuman humanoid", "crow-headed gadgeteer", "long metal beak, folded tool wings, spring legs, and monocle lens", "hammered copper and black feather steel", "cyan calibration sparks", "clever", "agile", "hopping-workbench-steps", "#52D7E8", "#B86F35"],
  ["candy-star-idol", "Candy Star Idol", "nonhuman humanoid", "star-headed confection mascot", "five-point candy head, tiny cape, spring boots, and microphone wand arm", "translucent candy glass and soft vinyl", "rainbow rhythm bursts", "cute", "bouncing", "stage-hops", "#FF77C8", "#68EAF2"],
  ["phantom-blade-wraith", "Phantom Blade Wraith", "nonhuman humanoid", "masked spectral swordsman", "empty horned mask, tapering ghost body, two forearm blades, and smoke tails", "black mist and violet edge metal", "cold purple soul flame", "dark", "spectral", "phase-dashes", "#9B72FF", "#24203F"],
  ["roseglass-ranger", "Roseglass Ranger", "nonhuman humanoid", "crystal rabbit ranger", "long rose-crystal ears, compact rabbit mask, spring legs, and prism bow arms", "pink crystal and fine gold filigree", "heart-shaped light arrows", "cute", "agile", "springing-archer-leaps", "#FF81C9", "#FFD66E"],
  ["zodiac-chimera-judge", "Zodiac Chimera Judge", "nonhuman humanoid", "many-mask zodiac arbiter", "three rotating animal masks, four arms, scale mantle, and ring staff", "ivory enamel and celestial bronze", "twelve constellation seals", "regal", "orbiting", "measured-orbital-steps", "#F0D58A", "#6358CF"],
  ["porcelain-koi-courtier", "Porcelain Koi Courtier", "nonhuman humanoid", "koi-masked porcelain courtier", "koi face, long fin sleeves, fan tail skirt, and pearl parasol fin", "blue-white porcelain and gold lacquer", "watercolor wave ribbons", "exquisite", "flowing", "courtly-glides", "#6CCAF2", "#F4E7D0"],
  ["radiant-jackal-herald", "Radiant Jackal Herald", "nonhuman humanoid", "golden jackal divine herald", "tall jackal head, sun staff, narrow armored torso, and twin banner tails", "black stone and radiant gold", "sunrise trumpet rays", "sacred", "marching", "heraldic-strides", "#FFD85C", "#1E2448"],
  ["celestial-garuda", "Celestial Garuda", "nonhuman humanoid", "avian sky deity", "eagle mask, four golden wings, taloned legs, and solar chakram arms", "white feather metal and celestial gold", "dawnfire feathers", "sacred", "winged", "vertical-power-flight", "#FFF0A8", "#65B8FF"],
  ["moonstone-golem-adept", "Moonstone Golem Adept", "nonhuman humanoid", "gentle moonstone martial golem", "rounded moon head, blocky limbs, crescent palms, and floating belt stones", "milky moonstone and indigo cord", "soft blue chi rings", "cute", "heavy", "rounded-martial-steps", "#CBDBFF", "#6F70C9"],
  ["mirror-mask-trickster", "Mirror-Mask Trickster", "nonhuman humanoid", "reflective mask illusionist", "faceted mirror face, ribbon torso, three asymmetric arms, and card-like heel fins", "mirror chrome and purple velvet", "duplicating prism flashes", "playful", "agile", "misdirection-dashes", "#B9F4FF", "#B352E8"],
  ["auric-seraph-construct", "Auric Seraph Construct", "nonhuman humanoid", "mechanical angel guardian", "blank gold face, six segmented wings, long spear arm, and gyroscope waist", "brushed gold and white ceramic", "sacred geometric light", "sacred", "winged", "ceremonial-flight", "#FFE27A", "#E9F6FF"],
  ["velvet-bat-duchess", "Velvet Bat Duchess", "nonhuman humanoid", "bat-faced night noble", "large bat ears, gem mask, cape wings, digitigrade feet, and crescent fan claws", "midnight velvet and ruby enamel", "crimson moon mist", "gothic", "gliding", "cape-wing-glides", "#C64C8E", "#32234F"],
  ["solar-ring-wyrm", "Solar Ring Wyrm", "mythic creature", "ring-bodied solar dragon", "serpentine dragon threaded through a broken sun ring, four small claws, and crown horns", "gold scale armor and black sunstone", "white-hot solar arcs", "sacred", "serpentine", "ring-coiling-flight", "#FFD54A", "#7A3E1A"],
  ["glacier-sky-dragon", "Glacier Sky Dragon", "mythic creature", "four-winged ice dragon", "long ice beak, four feather-crystal wings, two talons, and comet tail", "blue glacier crystal and silver feather plates", "snowstorm contrails", "exquisite", "winged", "high-altitude-soaring", "#A4EBFF", "#5474E8"],
  ["emberglass-hound", "Emberglass Hound", "mythic animal", "obsidian jackal hound", "wedge jackal face, tall ears, four powerful legs, ember chest fissure, and split flame tail", "black volcanic glass and small gold bands", "orange magma seams and broken-sun halo", "fierce", "prowling", "pouncing-quadruped-runs", "#FF7A24", "#17151E"],
  ["roseglass-fennec", "Roseglass Fennec", "mythic animal", "rose-crystal desert fox", "enormous faceted ears, petite fox body, curled gem tail, and heart prism chest", "transparent rose crystal and fine gold wire", "pink sparkle crescents", "cute", "bouncing", "light-desert-hops", "#FF8FD8", "#FFD56A"],
  ["starrail-gryphon", "Starrail Gryphon", "mythic creature", "cosmic gryphon courier", "eagle head, feline hindquarters, rail-shaped wings, and comet wheel tail", "navy armor feathers and star chrome", "cyan rail trails", "heroic", "winged", "rail-fast-flight", "#59D8FF", "#6D55E8"],
  ["prism-antler-cervid", "Prism Antler Cervid", "mythic animal", "rainbow crystal deer", "slender deer body, enormous prism antlers, split hooves, and jewel mane", "clear crystal and opal enamel", "refracted aurora rays", "exquisite", "poised", "weightless-deer-bounds", "#7EF0FF", "#E46EFF"],
  ["thundercloud-kirin", "Thundercloud Kirin", "mythic creature", "storm kirin", "dragon-deer head, cloud mane, four cloven legs, and lightning ribbon tail", "slate scales and vapor fleece", "white-blue thunder knots", "sacred", "buoyant", "cloud-gallops", "#70CFFF", "#F4F8FF"],
  ["moon-tide-leviathan", "Moon-Tide Leviathan", "mythic creature", "crescent sea leviathan", "whale-dragon head, long finned body, crescent dorsal sail, and pearl tail fan", "indigo scales and moon-pearl fins", "silver tidal rings", "mysterious", "swimming", "lunar-undulation", "#6AA7FF", "#E2DCFF"],
  ["duskfeather-phoenix", "Duskfeather Phoenix", "mythic creature", "twilight phoenix", "sharp bird head, broad dusk wings, long ribbon tail feathers, and ember crown", "violet metal feathers and orange glass", "sunset flame trails", "regal", "winged", "spiral-rising-flight", "#FF704E", "#6B3CD1"],
  ["voidmane-panther", "Voidmane Panther", "mythic animal", "black-hole panther", "low feline body, starfield mane, long blade tail, and gravity-ring shoulders", "matte void fur and blue crystal claws", "purple lensing arcs", "dark", "prowling", "silent-gravity-pounces", "#775CFF", "#11162D"],
  ["rune-shell-tortoise", "Rune-Shell Tortoise", "mythic animal", "ancient rune tortoise", "broad tortoise body, domed glyph shell, stout pillar legs, and lantern tail", "jade stone shell and bronze runes", "turquoise memory glyphs", "ancient", "heavy", "deliberate-tortoise-steps", "#42C7A0", "#C99A49"],
  ["aurora-snow-leopard", "Aurora Snow Leopard", "mythic animal", "polar-light snow leopard", "long feline body, oversized snow paws, aurora ribbon tail, and ice ear crests", "white fur plates and translucent ice", "green-violet aurora spots", "elegant", "prowling", "snowfield-bounds", "#8CF5E2", "#9F73FF"],
  ["comet-tail-tanuki", "Comet-Tail Tanuki", "mythic animal", "comet raccoon dog", "round masked face, squat body, huge ringed comet tail, and tiny meteor satchel shell", "soft midnight fur and meteor brass", "gold-blue comet sparks", "cute", "bouncing", "rolling-hops", "#FFD36C", "#5066C9"],
  ["abyssal-crown-whale", "Abyssal Crown Whale", "mythic creature", "deep-sea crown whale", "round whale head, six fin wings, crown lure, and long ribbon flukes", "dark velvet skin and pearl armor", "teal bioluminescent constellations", "mysterious", "swimming", "slow-pressure-swims", "#1FD4C5", "#1E3E7A"],
  ["clockwork-hummingbird", "Clockwork Hummingbird", "mechanical animal", "tiny clockwork hummingbird", "needle beak, rapid gear wings, teardrop body, and key-wound tail", "brass clockwork and teal enamel", "cyan timing sparks", "exquisite", "winged", "precision-hovering", "#4DE1DF", "#D99B3D"],
  ["lantern-jelly-drake", "Lantern Jelly Drake", "mythic creature", "jellyfish dragon hybrid", "small dragon head under a glowing dome, four veil fins, and luminous tentacle tail", "translucent gel and pearl scales", "aqua lantern glow", "dreamlike", "swimming", "pulsing-air-swims", "#62EAF1", "#B26BFF"],
  ["crystal-mantis", "Crystal Mantis", "mythic animal", "prismatic mantis", "triangular insect head, folded scythe arms, four stilt legs, and shard wings", "faceted emerald crystal and gold joints", "laser-thin rainbow cuts", "exquisite", "skittering", "stilted-mantis-dashes", "#62F0B8", "#FFC95C"],
  ["magma-armadillo", "Magma Armadillo", "mythic animal", "rolling lava armadillo", "armored round back, pointed snout, four digging claws, and segmented ember tail", "basalt shell and molten seams", "rolling fire rings", "fierce", "rolling", "armored-rolls", "#FF6A2B", "#3A2630"],
  ["spectral-axolotl", "Spectral Axolotl", "mythic animal", "ghostly axolotl", "wide smiling head, six feather gills, tiny legs, and long translucent tail", "opal gel and spirit mist", "blue-pink soul bubbles", "cute", "swimming", "gentle-water-hovers", "#8FE8FF", "#F195FF"],
  ["cosmic-orca", "Cosmic Orca", "mythic animal", "starfield orca", "bold orca body, crescent dorsal fin, wide flukes, and orbiting cheek rings", "deep-space skin and white moonstone patches", "constellation wake", "majestic", "swimming", "breaching-star-swims", "#507BFF", "#F2F3FF"],
  ["storm-hare-courier", "Storm Hare Courier", "mythic animal", "lightning hare", "long swept ears, compact runner body, oversized hind legs, and bolt tail", "blue storm fur and copper anklets", "yellow-white speed arcs", "cute", "agile", "thunder-hare-sprints", "#56BFFF", "#FFE35A"],
  ["jade-moon-serpent", "Jade Moon Serpent", "mythic creature", "wingless lunar serpent", "long jade body, crescent head fins, pearl whiskers, and fan tail", "polished jade scales and moon pearl", "pale lunar mist", "elegant", "serpentine", "floating-serpent-coils", "#4FD09E", "#E8F1D0"],
  ["obsidian-raven", "Obsidian Raven", "mythic animal", "black-glass prophecy raven", "angular raven beak, broad shard wings, crown feathers, and key-shaped talons", "smoked obsidian feathers and silver edges", "violet omen sparks", "gothic", "winged", "sharp-raven-flight", "#8762E8", "#171827"],
  ["sapphire-cerberus", "Sapphire Cerberus", "mythic creature", "three-headed crystal guardian hound", "three distinct canine heads, six ears, four legs, and braided crystal tail", "sapphire crystal armor and silver collars", "blue triune flame", "regal", "prowling", "guardian-hound-charges", "#479EFF", "#C9E8FF"],
  ["gilded-qilin-cub", "Gilded Qilin", "mythic creature", "golden cloud qilin", "deer-dragon face, single branch horn, four cloven legs, and cloud ribbon tail", "warm gold scales and white cloud fleece", "auspicious rainbow breath", "sacred", "buoyant", "cloud-prancing", "#FFD66B", "#F7F3DB"],
  ["starlight-red-panda", "Starlight Red Panda", "mythic animal", "stellar red panda", "round masked face, short legs, enormous ringed star tail, and comet ear tufts", "russet velvet fur and navy star plates", "tiny gold constellations", "cute", "bouncing", "playful-tree-free-hops", "#FF8B55", "#4A4DC7"],
  ["moonbell-owl", "Moonbell Owl", "mythic animal", "bell-bodied moon owl", "round owl face, bell torso, crescent wings, and clapper talons", "silver feathers and pale ceramic", "soft lunar chimes", "serene", "winged", "silent-bell-hovering", "#D9E7FF", "#7D83D8"],
  ["rainbow-shell-snail", "Rainbow-Shell Snail", "mythic animal", "prismatic racing snail", "soft round face, low foot, immense spiral shell, and two ribbon antennae", "opal shell glass and glossy gel", "rainbow slipstream", "cute", "gliding", "surprisingly-fast-glides", "#63EAD9", "#FF79C8"],
  ["velvet-cloud-baku", "Velvet Cloud Baku", "mythic creature", "dream-eating tapir spirit", "short trunk, rounded body, cloud ears, and curled nightmare tail", "midnight velvet and cloud fleece", "lavender dream spirals", "dreamlike", "buoyant", "sleepy-cloud-bounds", "#B59CFF", "#33437C"],
  ["neon-ribbon-lizard", "Neon Ribbon Lizard", "mythic animal", "arena ribbon lizard", "low sleek lizard body, fin crest, four gripping feet, and two light-ribbon tails", "dark scales and neon glass fins", "cyan-magenta race trails", "neon", "agile", "wall-running-sprints", "#2DE6FF", "#FF3CC7"],
  ["dawnwheel-seraph", "Dawnwheel Seraph", "divine entity", "faceless winged dawn deity", "blank sun mask, six metal wings, wheel halo, and two long blessing arms", "radiant gold and ivory crystal", "dawn rays and sacred geometry", "sacred", "winged", "majestic-hovering", "#FFE06A", "#FFF8DE"],
  ["moon-eclipse-archon", "Moon-Eclipse Archon", "divine entity", "crescent eclipse deity", "black moon face, two crescent horns, four veil arms, and ring throne", "black pearl and silver moon metal", "white corona fire", "mysterious", "orbiting", "eclipse-orbits", "#E6ECFF", "#3F376F"],
  ["thousand-eye-tempest", "Thousand-Eye Tempest", "divine entity", "many-eyed storm colossus", "cloud torso, six coil arms, many blue eyes, and tornado lower body", "charcoal cloudstone and lightning crystal", "branching electric veins", "divine", "pulsing", "storm-vortex-rotation", "#6BCBFF", "#47447F"],
  ["sacred-lotus-avatar", "Sacred Lotus Avatar", "divine entity", "lotus-born divine spirit", "petal face, four floating hands, seated lotus body, and moon halo", "white jade petals and pale gold", "rose-gold compassion light", "sacred", "buoyant", "lotus-hovering", "#FFE7F3", "#E7B855"],
  ["golden-sun-sphinx", "Golden Sun Sphinx", "divine entity", "solar sphinx", "lion body, smooth avian mask, broad gold wings, and sun-disc tail", "hammered gold and lapis enamel", "concentric solar glyphs", "regal", "poised", "sphinx-leaps-and-flight", "#FFD14A", "#3458B8"],
  ["void-gate-keeper", "Void Gate Keeper", "divine entity", "living portal guardian", "ring-shaped torso, one central eye, four armored arms, and tapering smoke feet", "black stone and violet event-glass", "gravity lens arcs", "dark", "orbiting", "portal-folding-steps", "#8B5CF6", "#131629"],
  ["starlight-naga-deity", "Starlight Naga Deity", "divine entity", "serpentine star deity", "masked cobra head, six jewel arms, long coiled tail, and constellation hood", "indigo scales and star gold", "white stellar mantras", "sacred", "serpentine", "ritual-coiling", "#5F75E8", "#F3D46B"],
  ["aurora-choir-spirit", "Aurora Choir Spirit", "divine entity", "many-voiced aurora apparition", "central smooth mask, layered ribbon body, six small choir faces, and fan halo", "translucent light silk and pearl", "harmonic aurora waves", "ethereal", "flowing", "choral-ribbon-flows", "#60F0D5", "#A777FF"],
  ["karmic-wheel-guardian", "Karmic Wheel Guardian", "divine entity", "wheel-bodied law guardian", "armored mask, eight-spoke torso wheel, four hands, and banner fins", "bronze scripture metal and jade", "turning gold seals", "ancient", "rolling", "wheel-marches", "#E6B84D", "#49B98F"],
  ["celestial-drum-god", "Celestial Drum God", "divine entity", "thunder-drum deity", "round drum torso, fierce mask, four mallet arms, and cloud-foot rings", "red lacquer and storm gold", "visible sound thunder", "fierce", "bouncing", "rhythmic-sky-stomps", "#F04E45", "#F3C84E"],
  ["mercury-messenger-idol", "Mercury Messenger Idol", "divine entity", "liquid-metal courier god", "winged smooth mask, droplet torso, blade feet, and twin orbit tablets", "mirror mercury and cyan glass", "silver speed script", "elegant", "gliding", "liquid-metal-dashes", "#BCEBFF", "#55A9D9"],
  ["diamond-thunder-deity", "Diamond Thunder Deity", "divine entity", "crystalline thunder god", "diamond head, four muscular crystal arms, bolt sash, and split prism legs", "clear diamond crystal and cobalt metal", "violet-white lightning", "divine", "heavy", "thunder-crystal-stomps", "#B8F2FF", "#6D4DFF"],
  ["dream-moon-protector", "Dream Moon Protector", "divine entity", "sleep guardian deity", "closed-eye crescent mask, blanket wings, four gentle hands, and pillow-cloud tail", "soft moon felt and pearl plates", "lavender sleep stars", "cute", "buoyant", "cradling-hover", "#D6C8FF", "#7E73C9"],
  ["scarlet-war-kami", "Scarlet War Kami", "divine entity", "nonhuman armored battle spirit", "oni-like lacquer mask, six banner arms, crescent armor skirt, and spear halo", "scarlet lacquer and black iron", "gold battle seals", "fierce", "marching", "banner-led-charges", "#E83D49", "#E7B64B"],
  ["ocean-pearl-sovereign", "Ocean Pearl Sovereign", "divine entity", "pearl-headed sea divinity", "giant pearl face, four wave arms, shell mantle, and finned lower vortex", "mother-of-pearl and aqua glass", "tidal crown light", "sacred", "flowing", "sovereign-tide-glides", "#7DE6E8", "#F2E3CD"],
  ["cosmic-hour-keeper", "Cosmic Hour Keeper", "divine entity", "timekeeping celestial idol", "clockless star face, four orbit arms, hourglass waist, and comet pendulum", "dark celestial bronze and blue crystal", "time-slice rings", "mysterious", "orbiting", "measured-time-orbits", "#58BCEB", "#B88AFF"],
  ["jade-comet-empress", "Jade Comet Empress", "divine entity", "faceless jade comet sovereign", "jade crown mask, six ribbon sleeves, long comet train, and twin fan moons", "translucent jade and celestial gold", "green-white comet fire", "regal", "flowing", "imperial-comet-glides", "#5CDAA3", "#E9C55B"],
  ["prism-crown-judicator", "Prism Crown Judicator", "divine entity", "rainbow law deity", "faceted blank face, giant prism crown, scale arms, and triangular robe legs", "white crystal and spectrum glass", "balanced rainbow beams", "exquisite", "poised", "geometric-steps", "#88ECFF", "#E56FFF"],
  ["eclipse-wing-oracle", "Eclipse Wing Oracle", "divine entity", "winged eclipse prophet", "dark bird mask, two vast crescent wings, eye halo, and ribbon talons", "black feathers and moon-silver edges", "violet corona omens", "gothic", "winged", "silent-oracle-flight", "#9D72F2", "#25213D"],
  ["constellation-king", "Constellation King", "divine entity", "star-map monarch construct", "crown of star points, hollow night face, four scepter arms, and orbit cloak", "midnight enamel and gold star wire", "moving constellation lines", "regal", "orbiting", "constellation-processions", "#FFD76B", "#465EC9"],
  ["aegis-pounce-unit", "Aegis Pounce Unit", "mecha creature", "white feline arena mecha", "low armored cat chassis, massive forepaws, turbine hips, and blade tail", "white ceramic armor and dark alloy", "cyan boost trails", "heroic", "mechanical", "powered-feline-sprints", "#53DAFF", "#F4F6FA"],
  ["rescue-drone-hound", "Rescue Drone Hound", "mecha creature", "orange medical rescue hound", "rounded canine cabin, four wheel-paws, rotor ears, and medic beacon tail", "orange polymer armor and white ceramic", "cyan diagnostic light", "cute", "rolling", "wheel-paw-patrols", "#FF8A43", "#EAF8FF"],
  ["neon-raptor-racer", "Neon Raptor Racer", "mecha creature", "digitigrade racing raptor machine", "narrow visor head, long spring legs, fin tail, and shoulder stabilizers", "black alloy and neon glass", "magenta-cyan speed ribbons", "neon", "mechanical", "digitigrade-boost-sprints", "#25E4FF", "#FF42C7"],
  ["orbit-crab-tank", "Orbit Crab Tank", "mecha creature", "spherical crab defense unit", "round core, six jointed legs, two shield claws, and orbital antenna ring", "gunmetal armor and brass joints", "blue targeting orbits", "tactical", "skittering", "six-leg-side-steps", "#4CAEFF", "#BA8742"],
  ["railgun-stag", "Railgun Stag", "mecha creature", "antlered artillery cervid", "sleek deer chassis, rail-shaped antlers, four piston legs, and capacitor tail", "navy alloy and silver ceramic", "electric rail charge", "heroic", "mechanical", "precision-mecha-bounds", "#65DFFF", "#5060C7"],
  ["pulse-wing-hummingbird", "Pulse-Wing Hummingbird", "mecha creature", "micro turbine hummingbird", "needle sensor beak, four pulse wings, tiny reactor body, and gyroscope tail", "rose-gold alloy and cyan glass", "rapid pulse rings", "exquisite", "winged", "microsecond-hovering", "#4FE3E4", "#E59A6F"],
  ["magma-drill-mole", "Magma Drill Mole", "mecha creature", "underground drill mole machine", "wedge drill nose, broad digging claws, low tracks, and exhaust tail", "black heat armor and copper drill plates", "orange thermal vents", "fierce", "mechanical", "burrowing-track-runs", "#FF782F", "#29242D"],
  ["glacier-bastion-bear", "Glacier Bastion Bear", "mecha creature", "heavy ice-defense bear mecha", "broad bear chassis, shield shoulders, four piston paws, and glacier reactor hump", "white armor and blue coolant crystal", "frost barrier grids", "tactical", "heavy", "armored-bear-marches", "#78D9FF", "#E9F2FF"],
  ["stealth-manta-jet", "Stealth Manta Jet", "mecha creature", "manta-shaped aerial stealth unit", "wide manta wings, pointed sensor head, two vector tails, and recessed engine eyes", "matte black composite and violet glass", "silent purple ion wake", "dark", "gliding", "stealth-wing-glides", "#7968ED", "#202339"],
  ["arc-lion-vanguard", "Arc Lion Vanguard", "mecha creature", "electric lion assault frame", "angular lion head, circular cable mane, four armored legs, and coil tail", "silver armor and cobalt alloy", "blue arc mane", "heroic", "mechanical", "assault-lion-charges", "#54C9FF", "#D8E4F2"],
  ["prism-samurai-frame", "Prism Samurai Frame", "mecha creature", "nonhuman samurai automaton", "faceless visor helm, two blade arms, digitigrade legs, and folding prism banner", "black titanium and rainbow crystal", "spectrum draw-cut arcs", "exquisite", "poised", "precision-draw-steps", "#72E8FF", "#D75CFF"],
  ["chrono-scarab-drone", "Chrono Scarab Drone", "mecha creature", "time-shifting scarab robot", "scarab shell, six mechanical legs, clock-ring wings, and needle head", "brass clockwork and blue crystal", "time echo rings", "mysterious", "skittering", "six-leg-time-skips", "#59BFE8", "#D2A84F"],
  ["lunar-rabbit-rover", "Lunar Rabbit Rover", "mecha creature", "rabbit-shaped moon rover", "two antenna ears, rounded cockpit face, four wheel legs, and dish tail", "white lunar ceramic and navy panels", "soft blue navigation beams", "cute", "rolling", "low-gravity-wheel-hops", "#78DFFF", "#EEF2FF"],
  ["void-gravity-spider", "Void Gravity Spider", "mecha creature", "eight-legged gravity machine", "central black-lens body, eight long legs, four stabilizer rings, and sensor crown", "black alloy and violet lens glass", "purple gravity distortions", "dark", "skittering", "wall-folding-spider-steps", "#8A60FF", "#191B2E"],
  ["solar-wyrm-mech", "Solar Wyrm Mech", "mecha creature", "segmented solar dragon machine", "long mechanical dragon spine, horned sensor head, four claw modules, and ring reactor tail", "gold armor and black heat ceramic", "white-orange solar plasma", "regal", "serpentine", "segmented-flight-coils", "#FFD24E", "#3C2A2A"]
];

const styleDirections = {
  ancient: "ancient relic craftsmanship, weathered detail, solemn silhouette",
  clever: "inventive gadget detail, alert proportions, agile readable shape",
  cute: "premium stylized collectible proportions, expressive nonhuman face, rounded early forms",
  dark: "mysterious high-contrast silhouette, controlled void colors, elegant menace",
  divine: "monumental sacred geometry, supernatural scale, radiant focal core",
  dreamlike: "soft luminous materials, surreal flowing contours, gentle mystery",
  elegant: "long disciplined curves, refined ornament, poised motion",
  ethereal: "translucent layered light, weightless topology, harmonic glow",
  exquisite: "jewel-like precision, ornate but readable details, luxury collectible finish",
  fierce: "arena-ready anatomy, forceful stance, sharp readable massing",
  gothic: "moonlit dark ornament, cathedral-like shape language without architecture, noble menace",
  heroic: "clear champion silhouette, athletic motion, confident focal pose",
  majestic: "broad noble silhouette, calm scale, celestial polish",
  mysterious: "occult visual logic, restrained glow, uncanny but appealing identity",
  neon: "competitive night-arena energy, sharp neon accents, speed-focused silhouette",
  playful: "toyetic motion, surprising asymmetry, bright confident character",
  regal: "ceremonial proportions, crown-like anatomy, disciplined luxury materials",
  sacred: "luminous holy iconography, serene power, ivory-gold polish",
  serene: "balanced silhouette, gentle expression, quiet luminous movement",
  tactical: "functional mecha anatomy, believable joints, compact battlefield clarity"
};

function color(hex) {
  return {
    red: Number.parseInt(hex.slice(1, 3), 16) / 255,
    green: Number.parseInt(hex.slice(3, 5), 16) / 255,
    blue: Number.parseInt(hex.slice(5, 7), 16) / 255
  };
}

function titleWords(value) {
  return value.split("-").join(" ");
}

const stageTemplates = [
  ["egg", "Core", "a compact sealed origin with only the persistent face or core marker and two folded anatomy hints", "compact origin silhouette; mature anatomy remains hidden"],
  ["hatchling", "First Spark", "a small appealing juvenile with simplified limbs and an oversized identity marker", "small juvenile proportions and a clearly readable first locomotion stance"],
  ["juvenile", "Pathfinder", "an athletic developing form that reveals the full locomotion system and first functional energy organ", "leaner mid-stage silhouette in active motion; visibly different from the hatchling"],
  ["ascended", "Ascendant", "a major structural ascension with changed stance, enlarged anatomy, and a mature combat or ritual function", "broad mature silhouette and a new pose; not merely extra armor"],
  ["legendary", "Crown", "the unmistakable apex form with crown anatomy, expanded scale, and a fully realized halo or energy system", "largest and most complete crown silhouette; visibly more magnificent than the ascended form"]
];

const themes = rows.map(([id, displayName, kind, existenceAnchor, silhouetteAnchor, material, energy, vibe, motionProfile, locomotionClass, accent, secondaryAccent]) => ({
  id,
  displayName,
  tags: [...new Set([kind, vibe, motionProfile, kind.includes("mecha") ? "mecha" : null, kind.includes("divine") ? "divine" : null, kind.includes("animal") || kind.includes("creature") ? "creature" : null].filter(Boolean))],
  subtitle: `${vibe} · ${kind}`,
  symbolName: kind.includes("mecha") ? "gearshape.2.fill" : kind.includes("divine") ? "sun.max.fill" : kind.includes("humanoid") ? "sparkles" : "pawprint.fill",
  lineageIntroduction: `${displayName} is an original ${kind} lineage built around ${existenceAnchor}, evolving through five structural forms without changing species or identity.`,
  existenceAnchor,
  silhouetteAnchor,
  silhouetteClass: `${id}-topology`,
  motionAnchor: `${displayName} moves through ${titleWords(locomotionClass)} while keeping ${silhouetteAnchor}.`,
  locomotionClass,
  materialAnchor: `${displayName}: ${material}`,
  energyAnchor: `${displayName}: ${energy}`,
  motionProfile,
  artStyle: `${vibe}; ${styleDirections[vibe]}`,
  accent: color(accent),
  secondaryAccent: color(secondaryAccent),
  forms: stageTemplates.map(([stage, suffix, introduction, visualAnchor]) => ({
    stage,
    name: `${displayName} ${suffix}`,
    introduction: `${displayName} appears as ${introduction}, preserving ${existenceAnchor}.`,
    visualAnchor: `${displayName}: ${visualAnchor}; persistent anatomy is ${silhouetteAnchor}.`
  }))
}));

if (themes.length !== 100) throw new Error(`Expansion must define exactly 100 lineages; found ${themes.length}.`);
for (const key of ["id", "displayName", "existenceAnchor", "silhouetteAnchor"]) {
  if (new Set(themes.map((theme) => theme[key])).size !== themes.length) throw new Error(`Duplicate ${key} in expansion plan.`);
}

function lineupPrompt(theme) {
  const formLines = theme.forms.map((form, index) => `${index + 1}. ${form.name}: ${form.introduction} Visual requirement: ${form.visualAnchor}`).join("\n");
  return `Create one production asset: a clean horizontal five-stage evolution lineup for the original Sidekin desktop companion ${theme.displayName}.

Identity bible:
- Existence type: ${theme.existenceAnchor}.
- Persistent silhouette anatomy: ${theme.silhouetteAnchor}.
- Materials: ${theme.materialAnchor}.
- Energy motif: ${theme.energyAnchor}.
- Movement logic: ${theme.motionAnchor}.
- Art mood: ${theme.artStyle}.

Canvas and mandatory slot layout:
- Very wide 2:1 landscape canvas with a perfectly flat, uniform pure green #00FF00 background edge to edge.
- Exactly five separate full-body subjects in one straight horizontal row, one stage centered in each invisible equal-width cell.
- Scale every subject to stay completely inside its own cell. Leave an uninterrupted vertical gutter of pure green between every neighboring pair from top edge to bottom edge. No limb, tail, wing, halo, particle, ribbon, or effect may cross a gutter.
- No overlap, touching, cropping, floor, cast shadow, scenery, text, numbers, labels, dividers, frame, UI, logo, or watermark. Keep pure green out of every subject.

Stages, left to right:
${formLines}

Continuity and quality rules:
- These are five ages of exactly the same individual and species. Preserve the same face or primary core, signature palette, defining material, and at least three identity anchors in all five.
- Make each stage structurally and proportionally different with a distinct pose. Never produce five recolors or the same body with more accessories.
- The legendary form must be the largest, most complete, and most visually impressive form, clearly surpassing the ascended form while staying the same species.
- Polished high-end original competitive-game character render, premium collectible companion, crisp small-size readability, controlled specular detail, production-quality anatomy or construction.
- Any humanoid form must remain unmistakably nonhuman: no real person, human child, realistic human skin, realistic human hair, or ordinary human face.
- Exactly these five subjects and nothing else.`;
}

await fs.mkdir(outputRoot, { recursive: true });
await fs.writeFile(path.join(outputRoot, "lineages.json"), `${JSON.stringify({ schemaVersion: 1, themes }, null, 2)}\n`);
const promptRoot = path.join(outputRoot, "Prompts");
await fs.mkdir(promptRoot, { recursive: true });
for (const theme of themes) {
  await fs.writeFile(path.join(promptRoot, `${theme.id}.txt`), `${lineupPrompt(theme)}\n`);
}

const progressPath = path.join(outputRoot, "progress.json");
try {
  await fs.access(progressPath);
} catch {
  await fs.writeFile(progressPath, `${JSON.stringify({ schemaVersion: 1, generatedLineups: [], processedLineages: [], reviewedLineages: [] }, null, 2)}\n`);
}

console.log(`Generated a tag-based 100-lineage expansion plan and ${themes.length} five-stage lineup prompts.`);
