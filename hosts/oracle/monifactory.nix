{ ... }:
{
  mySystem.services.monifactory = {
    enable = true;
    players = [ "gegnep" ];
    # Client (Prism) must install the SAME versions. Comment = what to pick.
    mods = [
      # CC: Tweaked 1.120.2
      "https://cdn.modrinth.com/data/gu7yAYhd/versions/gRtcHJd8/cc-tweaked-1.20.1-forge-1.120.2.jar"
      # Advanced Peripherals 0.7.48r
      "https://cdn.modrinth.com/data/SOw6jD6x/versions/mIP0ApJY/AdvancedPeripherals-1.20.1-0.7.48r.jar"
      # Advanced AE 1.3.6
      "https://cdn.modrinth.com/data/rxYaglEe/versions/d83Wdhdn/AdvancedAE-1.3.6-1.20.1.jar"
      # GeckoLib 4.8.4 (Advanced AE dep; not in the pack)
      "https://cdn.modrinth.com/data/8BmcQJ2H/versions/aC5KMoNg/geckolib-forge-1.20.1-4.8.4.jar"
      # Tempad 2.3.4 (Resourceful Lib/Config already in pack)
      "https://cdn.modrinth.com/data/gKNwt7xu/versions/tfbtBBGB/tempad-forge-1.20.1-2.3.4.jar"
      # Compact Machines 6.0.3 (CurseForge only)
      "https://mediafilez.forgecdn.net/files/6000/230/compactmachines-forge-6.0.3.jar"
      # Architect's Palette 1.3.6.1
      "https://cdn.modrinth.com/data/vt0VyseM/versions/bZg21BDb/Architects-Palette-1.20.1-1.3.6.1.jar"
      # Project Red Illumination 4.21.0 (must equal the pack's PR Core 4.21.0)
      "https://cdn.modrinth.com/data/9a4Zqq1k/versions/gY5ES9Az/ProjectRed-1.20.1-4.21.0-illumination.jar"
      # Chunky 1.3.146: server-only pregen. Delete this line once pregen is done.
      "https://cdn.modrinth.com/data/fALzjamp/versions/4FTDk9wv/Chunky-1.3.146.jar"
    ];
  };
}
