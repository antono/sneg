# Not in nixpkgs, and only kicad-mcp wants it — so it stays private to that
# package rather than becoming another attribute in ../default.nix.
#
# The schematic half of kicad-mcp is built on this: `python/commands/*.py`
# import `skip.Schematic` behind try/except, so without it the board tools
# still work and every schematic tool degrades to an error at call time.
{
  lib,
  buildPythonPackage,
  fetchPypi,
  setuptools,
  sexpdata,
}:

buildPythonPackage rec {
  pname = "kicad-skip";
  version = "0.2.5";

  src = fetchPypi {
    inherit pname version;
    hash = "sha256-3GtHIV2h6C8syFZ/Dx6OWsgpf14ZQdlnGS4EM4DgjIM=";
  };

  pyproject = true;

  build-system = [ setuptools ];

  dependencies = [ sexpdata ];

  # The distribution is `kicad-skip`; the module it installs is `skip`.
  pythonImportsCheck = [ "skip" ];

  meta = {
    description = "S-expression manipulation of KiCad schematic and layout files";
    homepage = "https://github.com/psychogenic/kicad-skip";
    license = lib.licenses.lgpl21Only;
    maintainers = with lib.maintainers; [ antono ];
  };
}
