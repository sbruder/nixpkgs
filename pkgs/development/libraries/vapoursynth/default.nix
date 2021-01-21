{ buildEnv, lib, stdenv, fetchFromGitHub, pkg-config, autoreconfHook, makeWrapper
, vapoursynth
, zimg, libass, python3, libiconv
, ApplicationServices
, ocrSupport ?  false, tesseract ? null
, imwriSupport? true,  imagemagick7 ? null
}:

assert ocrSupport   -> tesseract != null;
assert imwriSupport -> imagemagick7 != null;

with lib;

stdenv.mkDerivation rec {
  pname = "vapoursynth";
  version = "R52";

  src = fetchFromGitHub {
    owner  = "vapoursynth";
    repo   = "vapoursynth";
    rev    = version;
    sha256 = "1krfdzc2x2vxv4nq9kiv1c09hgj525qn120ah91fw2ikq8ldvmx4";
  };

  patches = [
    ./plugin-path-environment-variable.patch
  ];

  nativeBuildInputs = [ pkg-config autoreconfHook makeWrapper ];
  buildInputs = [
    zimg libass
    (python3.withPackages (ps: with ps; [ sphinx cython ]))
  ] ++ optionals stdenv.isDarwin [ libiconv ApplicationServices ]
    ++ optional ocrSupport   tesseract
    ++ optional imwriSupport imagemagick7;

  configureFlags = [
    (optionalString (!ocrSupport)   "--disable-ocr")
    (optionalString (!imwriSupport) "--disable-imwri")
  ];

  enableParallelBuilding = true;

  passthru = {
    # If vapoursynth is added to the build inputs of mpv and then
    # used in the wrapping of it, we want to know once inside the
    # wrapper, what python3 version was used to build vapoursynth so
    # the right python3.sitePackages will be used there.
    inherit python3;

    withPlugins = plugins: let
      pythonEnvironment = python3.buildEnv.override {
        extraLibs = plugins;
      };
    in
    buildEnv {
      name = "${vapoursynth.name}-with-plugins";
      paths = [ vapoursynth ] ++ plugins;
      buildInputs = [ makeWrapper ];
      postBuild = ''
        # If vapoursynth is the only path providing a binary, buildEnv will
        # link bin to the vapoursynth derivation, which is write protected.
        # Then wrapProgram will not work, since it overwrites/adds files in
        # bin.
        mkdir $out/bin_
        for binary in $out/bin/*; do
            # skip wrapProgram original files
            [[ $binary == .* ]] && continue

            makeWrapper $(realpath $binary) $out/bin_/$(basename $binary) \
                --set VAPOURSYNTH_PLUGIN_PATH $out/lib/vapoursynth \
                --prefix PYTHONPATH : ${pythonEnvironment}/${python3.sitePackages}
        done
        rm -rf $out/bin
        mv $out/bin_ $out/bin
      '';

      passthru = {
        inherit python3;
      };
    };
  };

  postInstall = ''
    wrapProgram $out/bin/vspipe \
        --prefix PYTHONPATH : $out/${python3.sitePackages}
  '';

  meta = with lib; {
    description = "A video processing framework with the future in mind";
    homepage    = "http://www.vapoursynth.com/";
    license     = licenses.lgpl21;
    platforms   = platforms.x86_64;
    maintainers = with maintainers; [ rnhmjoj sbruder tadeokondrak ];
  };
}
