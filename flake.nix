{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = {self, nixpkgs, flake-utils}: flake-utils.lib.eachDefaultSystem (system:
    let
      pkgs = import nixpkgs { inherit system; };
      yaMusic = pkgs.stdenv.mkDerivation {
        name = "yandex-download-music";
        version = "v1.5";
        src = ./.;
  
        nativeBuildInputs = [
          pkgs.makeWrapper
        ];
  
        buildInputs = [
          pkgs.perl
          (pkgs.buildEnv {
            name = "rt-perl-deps";
            paths = with pkgs.perlPackages; (requiredPerlModules [
                FileUtil
                MP3Tag
                GetoptLongDescriptive LWPUserAgent
                LWPProtocolHttps
                HTTPCookies
                MozillaCA
            ]);
          })
        ];
  
        installPhase = ''
          mkdir -p $out/bin
          cp src/ya.pl $out/bin/ya-music
          # cat src/ya.pl | perl -p -e "s/basename\(__FILE__\)/'ya-music'/g" > $out/bin/ya-music
          # chmod +x $out/bin/ya-music
        '';
  
        postFixup = ''
          # wrapProgram will rename ya-music into .ya-music-wrapped
          # so replace all __FILE__ calls
          substituteInPlace $out/bin/ya-music \
            --replace "basename(__FILE__)" "'ya-music'"
  
          wrapProgram $out/bin/ya-music \
            --prefix PERL5LIB : $PERL5LIB
        '';
      };
    in
    {
      packages.default = yaMusic;
      apps.default = flake-utils.lib.mkApp { drv = yaMusic; };
    }
  );
}
