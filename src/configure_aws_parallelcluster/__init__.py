from importlib.metadata import version

# See: https://github.com/python-poetry/poetry/pull/2366#issuecomment-652418094
# For info on poetry versionion for Python < 3.8
__version__ = version(__name__)
