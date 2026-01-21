{
  pre-commit,
  python3Packages,
  fetchFromGitHub,
}:
let
  pdftext = python3Packages.buildPythonPackage rec {
    pname = "pdftext";
    version = "0.6.3";
    pyproject = true;

    src = fetchFromGitHub {
      owner = "datalab-to";
      repo = "pdftext";
      rev = "v${version}";
      hash = "sha256-EGVjzjDWtdcEPX//cOm5+xm9FvX0aP+h6fsD25hC8gA=";
    };

    build-system = with python3Packages; [
      poetry-core
    ];

    dependencies = with python3Packages; [
      click
      pypdfium2
      pydantic
      pydantic-settings
    ];

    pythonRemoveDeps = [
      "pypdfium"
    ];
  };

  surya-ocr = python3Packages.buildPythonPackage rec {
    pname = "surya-ocr";
    version = "0.17.0";
    pyproject = true;

    src = fetchFromGitHub {
      owner = "datalab-to";
      repo = "surya";
      rev = "v${version}";
      hash = "sha256-wkkif0eWuWmaygSpjSO7UL53qIgQLRrdMk7OsTe4wm8=";
    };

    build-system = with python3Packages; [
      poetry-core
    ];

    dependencies = with python3Packages; [
      transformers
      torch
      pydantic
      pydantic-settings
      python-dotenv
      pillow
      pypdfium2
      filetype
      click
      platformdirs
      opencv-python-headless
      einops
      pre-commit
    ];

    pythonRelaxDeps = [
      "opencv-python-headless"
      "pillow"
    ];

    pythonRemoveDeps = [
      "pypdfium"
    ];

    # Tests require network access
    enabledTests = [
      "test_recognition_clean_math"
      "test_recognition_clean_math_preserve_text"
    ];
  };
in
python3Packages.buildPythonApplication rec {
  pname = "marker-pdf";
  version = "1.10.1";
  pyproject = true;

  src = fetchFromGitHub {
    owner = "datalab-to";
    repo = "marker";
    rev = "v${version}";
    hash = "sha256-3UN+6MdwLkMrwI473K5bammGtBflm02/sMWBWSiI8gk=";
  };

  postPatch = ''
    substituteInPlace marker/settings.py \
      --replace-fail 'os.path.dirname(os.path.dirname(os.path.abspath(__file__)))' 'os.getcwd()'
  '';

  build-system = with python3Packages; [
    poetry-core
  ];

  dependencies = with python3Packages; [
    pillow
    anthropic
    click
    filetype
    ftfy
    google-genai
    markdown2
    markdownify
    openai
    pdftext
    pre-commit
    pydantic
    pydantic-settings
    python-dotenv
    rapidfuzz
    regex
    scikit-learn
    surya-ocr
    torch
    tqdm
    transformers
    streamlit
  ];

  nativeCheckInputs = with python3Packages; [
    jupyter
    datasets
    fastapi
    uvicorn
    python-multipart
    pytest
    pytest-mock
    apted
    lxml
    tabulate
    latex2mathml
    playwright
  ];

  pythonRelaxDeps = [
    "pillow"
    "anthropic"
    "openai"
    "regex"
  ];

  enabledTestPaths = [
    "tests/config"
  ];

  meta.mainProgram = "marker_single";
}
