// Curated free assets for game devs. Licenses checked 2026-11-22 on each site.
// license: short label shown on the page. note: what to watch out for.
// Served as /api/packs (the plugin's Packs tab) and rendered on /assets.

const PER_ASSET = "Per asset";

module.exports = {
  checked: "2026-11-22",
  categories: [
    {
      id: "sfx", name: "Sound effects",
      items: [
        { name: "Kenney audio packs", url: "https://kenney.nl/assets/category:Audio", license: "CC0", desc: "Clean UI, impact and interface sound packs." },
        { name: "Freesound", url: "https://freesound.org", license: PER_ASSET, note: "Skip anything marked NonCommercial. Free account to download.", desc: "Huge library of recorded sounds." },
        { name: "Sonniss GDC bundle", url: "https://sonniss.com/gameaudiogdc", license: "Own license", note: "Free for commercial use, no credit. Don't re-share the files.", desc: "Yearly multi-GB pro sound effect bundles." },
        { name: "Pixabay sound effects", url: "https://pixabay.com/sound-effects/", license: "Pixabay license", note: "No credit needed. Don't re-share the files on their own.", desc: "Stock sound effects." },
        { name: "ChipTone", url: "https://sfbgames.itch.io/chiptone", license: "CC0", desc: "Make retro sound effects yourself." },
        { name: "jsfxr", url: "https://sfxr.me", license: "Free to use", desc: "Classic sfxr generator in the browser." },
      ],
    },
    {
      id: "music", name: "Music",
      items: [
        { name: "Incompetech", url: "https://incompetech.com/music/royalty-free/", license: "CC BY 4.0", note: "Credit Kevin MacLeod.", desc: "Big catalog of music in every genre." },
        { name: "Music Loop Bundle", url: "https://tallbeard.itch.io/music-loop-bundle", license: "CC0", desc: "Looping game music, name your own price." },
        { name: "Pixabay music", url: "https://pixabay.com/music/", license: "Pixabay license", note: "No credit needed. Don't re-share the files on their own.", desc: "Background music tracks." },
        { name: "OpenGameArt music", url: "https://opengameart.org/art-search-advanced?field_art_type_tid%5B%5D=12", license: PER_ASSET, note: "Check each track's license.", desc: "Community game music archive." },
      ],
    },
    {
      id: "vfx", name: "VFX and shaders",
      items: [
        { name: "Kenney Particle Pack", url: "https://kenney.nl/assets/particle-pack", license: "CC0", desc: "Smoke, fire, sparks, magic, ready for particles." },
        { name: "Godot Shaders", url: "https://godotshaders.com", license: PER_ASSET, note: "Mostly CC0 or MIT. Shadertoy ports need credit.", desc: "Community shaders made for Godot." },
        { name: "itch.io free particles", url: "https://itch.io/game-assets/free/tag-particles", license: PER_ASSET, note: "Each creator sets the license.", desc: "Free effect sprite sheets." },
      ],
    },
    {
      id: "art", name: "2D art and sprites",
      items: [
        { name: "Kenney 2D packs", url: "https://kenney.nl/assets", license: "CC0", desc: "Hundreds of consistent sprite packs." },
        { name: "CraftPix freebies", url: "https://craftpix.net/freebies/", license: "Own license", note: "Free for commercial use. Don't re-share the source files.", desc: "Polished characters, GUIs and backgrounds." },
        { name: "itch.io free sprites", url: "https://itch.io/game-assets/free/tag-sprites", license: PER_ASSET, note: "Each creator sets the license.", desc: "Thousands of free sprite packs." },
        { name: "OpenGameArt", url: "https://opengameart.org", license: PER_ASSET, note: "BY-SA and GPL art comes with share-alike rules.", desc: "Community archive of open game art." },
      ],
    },
    {
      id: "pixel", name: "Pixel art and tilesets",
      items: [
        { name: "Tiny Dungeon", url: "https://kenney.nl/assets/tiny-dungeon", license: "CC0", desc: "16x16 dungeon tiles and characters." },
        { name: "Pixel Platformer", url: "https://kenney.nl/assets/pixel-platformer", license: "CC0", desc: "Platformer tiles, enemies and items." },
        { name: "1-Bit Pack", url: "https://kenney.nl/assets/1-bit-pack", license: "CC0", desc: "Over a thousand one-color tiles." },
        { name: "DungeonTileset II", url: "https://0x72.itch.io/dungeontileset-ii", license: "CC0", desc: "Popular 16x16 dungeon set by 0x72." },
        { name: "itch.io free tilesets", url: "https://itch.io/game-assets/free/tag-tileset", license: PER_ASSET, note: "Each creator sets the license.", desc: "Free tilesets for every style." },
        { name: "Lospec palettes", url: "https://lospec.com/palette-list", license: "Free", desc: "Thousands of pixel art color palettes." },
      ],
    },
    {
      id: "3d", name: "3D",
      items: [
        { name: "Kenney 3D packs", url: "https://kenney.nl/assets", license: "CC0", desc: "Low-poly models for every genre." },
        { name: "Quaternius", url: "https://quaternius.com", license: "Own license", note: "Free for commercial use. Don't re-share the models.", desc: "Low-poly characters and props." },
        { name: "Poly Haven", url: "https://polyhaven.com", license: "CC0", desc: "HDRIs, PBR textures and models." },
        { name: "ambientCG", url: "https://ambientcg.com", license: "CC0", desc: "PBR materials and HDRIs." },
      ],
    },
    {
      id: "ui", name: "Fonts, UI and icons",
      items: [
        { name: "Kenney UI Pack", url: "https://kenney.nl/assets/ui-pack", license: "CC0", desc: "Buttons, panels and sliders." },
        { name: "game-icons.net", url: "https://game-icons.net", license: "CC BY 3.0", note: "Credit the icon authors.", desc: "4000+ game icons as SVG and PNG." },
        { name: "Google Fonts", url: "https://fonts.google.com", license: "Mostly OFL", desc: "Free fonts you can ship in a game." },
      ],
    },
    {
      id: "tools", name: "Free tools",
      items: [
        { name: "Piskel", url: "https://www.piskelapp.com", license: "Open source", desc: "Sprite and animation editor in the browser." },
        { name: "LibreSprite", url: "https://libresprite.github.io", license: "GPL", desc: "Free pixel art editor." },
        { name: "LDtk", url: "https://ldtk.io", license: "Open source", desc: "Modern 2D level editor." },
        { name: "Tiled", url: "https://www.mapeditor.org", license: "Open source", desc: "Classic tile map editor." },
        { name: "Audacity", url: "https://www.audacityteam.org", license: "Open source", desc: "Cut and clean up audio." },
        { name: "Blender", url: "https://www.blender.org", license: "Open source", desc: "3D modeling and animation." },
      ],
    },
  ],
};
