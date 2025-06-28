# Tests for R2MIDI

This directory contains tests for the R2MIDI application.

## Structure

- `tests/unit/`: Unit tests for individual components
  - `test_models.py`: Tests for the server-side models
  - `test_device_manager.py`: Tests for the DeviceManager class
  - `test_midi_utils.py`: Tests for the MidiUtils class
  - `test_ui_launcher.py`: Tests for the UILauncher class
  - `test_main.py`: Tests for the main FastAPI application
  - `midi_preset_client/`: Tests for the client-side components
    - `test_models.py`: Tests for the client-side models
    - `test_api_client.py`: Tests for the client-side API client

## Running Tests

To run all tests:

```bash
pytest tests/
```

To run a specific test file:

```bash
pytest tests/unit/test_models.py
```

To run tests with coverage:

```bash
pytest --cov=. tests/
```

To generate a coverage report:

```bash
pytest --cov=. --cov-report=html tests/
```

This will generate a coverage report in the `htmlcov` directory.

## Test Dependencies

The tests require the following dependencies:

- pytest
- pytest-asyncio
- pytest-mock
- pytest-cov
- httpx

These dependencies are specified in the `pyproject.toml` file under the `[project.optional-dependencies]` section.

To install the test dependencies:

```bash
pip install -e ".[test]"
```

## Writing Tests

When writing tests, follow these guidelines:

1. Use descriptive test names that indicate what is being tested
2. Use the `unittest` framework for simple tests
3. Use `pytest` fixtures and markers for more complex tests
4. Mock external dependencies to isolate the code being tested
5. Test both success and error cases
6. Test edge cases and boundary conditions
7. Use assertions to verify the expected behavior