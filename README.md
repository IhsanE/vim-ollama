# vim-ollama

Integrate AI capabilities into Vim using Ollama, providing seamless access to local large language models directly from your editor.

## Features

- Automatic installation and setup of Ollama
- Process text with AI directly within Vim
- Support for custom prompts and questions
- Configurable model selection and parameters
- Cross-platform compatibility (Linux, macOS, Windows*)

*Windows requires manual Ollama installation

## Installation

### Using vim-plug

```vim
Plug 'ihsane/vim-ollama', { 'do': ':call ollama#InstallDependencies()' }
