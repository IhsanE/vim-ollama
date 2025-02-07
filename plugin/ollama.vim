" ollama.vim - AI-powered text processing in Vim
" Maintainer: github.com/ihsane 
" Version: 2.0
" License: MIT

if exists('g:loaded_ollama') || &cp
    finish
endif
let g:loaded_ollama = 1

" Configuration defaults
let g:ollama_model = get(g:, 'ollama_model', 'llama2')
let g:ollama_timeout = get(g:, 'ollama_timeout', 30)
let g:ollama_window_position = get(g:, 'ollama_window_position', 'rightbelow')
let g:ollama_window_size = get(g:, 'ollama_window_size', 15)
let g:ollama_auto_install_model = get(g:, 'ollama_auto_install_model', 1)

" Installation Management Functions
function! s:DetectOS()
    if has('win32') || has('win64')
        return 'windows'
    elseif has('macunix')
        return 'macos'
    elseif has('unix')
        return 'linux'
    endif
    return 'unknown'
endfunction

function! s:HasCommand(cmd)
    if !executable(a:cmd)
        call s:DisplayError("Command '" . a:cmd . "' not found. Please install it and ensure it is in your PATH.")
        return 0
    endif
    return 1
endfunction

function! RestoreStatusLine()
    let &statusline = ''
    redraw
endfunction

function! s:InstallOllama()
    let l:os = s:DetectOS()
    
    if l:os == 'unknown'
        call s:DisplayError('Unsupported operating system')
        return 0
    endif
    
    call s:SetStatus('Installing Ollama...')
    
    if l:os == 'macos'
        return s:InstallMacos()
    elseif l:os == 'linux'
        return s:InstallLinux()
    elseif l:os == 'windows'
        return s:InstallWindows()
    endif
endfunction

function! s:InstallMacos()
    if !s:HasCommand('brew')
        call s:SetStatus('Installing Homebrew...')
        let l:brew_install = system('/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"')
        if v:shell_error
            call s:DisplayError('Failed to install Homebrew')
            return 0
        endif
    endif
    
    call s:SetStatus('Installing Ollama via Homebrew...')
    let l:install_result = system('brew install ollama')
    if v:shell_error
        call s:DisplayError('Failed to install Ollama')
        return 0
    endif
    
    return s:StartOllamaService()
endfunction

function! s:InstallLinux()
    call s:SetStatus('Installing Ollama via installation script...')
    let l:install_cmd = 'curl -fsSL https://ollama.ai/install.sh | sh'
    let l:install_result = system(l:install_cmd)
    
    if v:shell_error
        call s:DisplayError('Failed to install Ollama')
        return 0
    endif
    
    return s:StartOllamaService()
endfunction

function! s:InstallWindows()
    call s:DisplayError('Automatic installation on Windows is not supported. Please visit https://ollama.ai/download')
    return 0
endfunction

function! s:InstallModel(model)
    if !s:HasCommand('ollama')
        call s:DisplayError('Ollama must be installed before installing models')
        return 0
    endif
    
    call s:SetStatus('Installing model ' . a:model . '...')
    let l:install_result = system('ollama pull ' . a:model)
    
    if v:shell_error
        call s:DisplayError('Failed to install model ' . a:model)
        return 0
    endif
    
    call s:SetStatus('Model ' . a:model . ' installed successfully')
    return 1
endfunction

function! ollama#InstallDependencies()
    let l:ollama_installed = s:HasCommand('ollama')
    
    if !l:ollama_installed
        let l:install_choice = confirm('Ollama is not installed. Would you like to install it now?', "&Yes\n&No", 1)
        if l:install_choice != 1
            return 0
        endif
        
        if !s:InstallOllama()
            return 0
        endif
    endif
    
    " Check if the configured model exists
    let l:model_check = system('ollama list | grep ' . g:ollama_model)
    if v:shell_error && g:ollama_auto_install_model
        call s:SetStatus('Model ' . g:ollama_model . ' not found. Installing...')
        if !s:InstallModel(g:ollama_model)
            return 0
        endif
    endif
    
    return 1
endfunction

function! s:StartOllamaService()
    call s:SetStatus('Starting Ollama service...')
    
    let l:os = s:DetectOS()
    if l:os == 'macos'
        call system('brew services start ollama')
    elseif l:os == 'linux'
        call system('systemctl --user start ollama')
    endif
    
    " Wait for service to start
    let l:retries = 0
    while l:retries < 10
        sleep 1
        if s:HasCommand('ollama')
            return 1
        endif
        let l:retries += 1
    endwhile
    
    call s:DisplayError('Ollama service failed to start')
    return 0
endfunction

" Core Plugin Functions
function! s:EnsureCRWindow()
    if !exists('g:ollama_cr_window')
        let g:ollama_cr_window = 'Ollama-Output'
    endif
endfunction

function! s:OpenCRWindow(output)
    call s:EnsureCRWindow()
    execute "rightbelow new" g:ollama_cr_window
    setlocal buftype=nofile
    setlocal bufhidden=hide
    setlocal noswapfile
    setlocal nobuflisted
    setlocal filetype=markdown
    setlocal wrap
    setlocal linebreak
    setlocal nonumber
    setlocal modifiable
    
    execute 'normal! ggdG'
    let lines = split(a:output, "\n")
    call append(0, lines)
    normal! gg
endfunction

function! s:EscapeInput(input)
    let escaped = substitute(a:input, "'", "'\"'\"'", "g")
    let escaped = substitute(escaped, '"', '\\"', "g")
    let escaped = substitute(escaped, '`', '\\`', "g")
    let escaped = substitute(escaped, '\$', '\\$', "g")
    let escaped = substitute(escaped, '%', '%%', "g") " Escape % for printf
    let escaped = substitute(escaped, '\n', '\\n', "g")
    return escaped
endfunction

function! s:SetStatus(message)
    echohl Special
    echo a:message
    echohl None
endfunction

function! s:DisplayError(message)
    echohl ErrorMsg
    echomsg 'Error: ' . a:message
    echohl None
endfunction

function! s:ProcessWithOllama(mode, with_question) abort
    let selection = ''

    " Get selected text
    if a:mode ==# 'v'
        let [line_start, column_start] = getpos("'<")[1:2]
        let [line_end, column_end] = getpos("'>")[1:2]
        let lines = getline(line_start, line_end)

        if len(lines) == 0
            call s:DisplayError("No text selected")
            return
        endif

        if len(lines) == 1
            let selection = lines[0][column_start - 1:column_end - 1]
        else
            let lines[-1] = lines[-1][: column_end - 1]
            let lines[0] = lines[0][column_start - 1:]
            let selection = join(lines, "\n")
        endif
    else
        let selection = join(getline(1, '$'), "\n")
    endif

    if empty(selection)
        call s:DisplayError("No text to process")
        return
    endif

    let escaped_selection = s:EscapeInput(selection)

    " Handle user input for question
    let prompt = ''
    if a:with_question
        let prompt = input('Enter your question: ')
        if empty(prompt)
            call s:DisplayError("Question required")
            return
        endif
        let escaped_prompt = s:EscapeInput(prompt)
    endif

    " Check if model is available
    let check_command = "ollama list"
    call s:SetStatus('Checking for model...')
    let check_output = system(check_command)

    if match(check_output, g:ollama_model) < 0
        " Model not found, open terminal to download
        call s:SetStatus('Model not found. Downloading...')

        " Open a terminal split to run `ollama pull`
        execute 'belowright 10split | terminal ++close ollama pull ' . g:ollama_model

        " Inform the user to monitor the terminal
        echom "Terminal opened. Monitor the download and close the terminal when it completes."
        return
    endif

    " Recheck if the model is available
    let recheck_output = system(check_command)
    if match(recheck_output, g:ollama_model) < 0
        call s:DisplayError("Failed to download model: " . g:ollama_model)
        return
    endif

    call s:SetStatus('Model download complete.')

    " Build the command
    let command = ''
    if a:with_question
        let command = printf(
        \   "echo '%s\nQuestion: %s' | ollama run %s 2> /dev/null | tr '\\0' '\\n' | sed -u 's/\r//g'",
        \   escaped_selection,
        \   escaped_prompt,
        \   g:ollama_model
        \)
    else
        let command = printf(
        \   "echo '%s' | ollama run %s 2>&1 /dev/null | tr '\\0' '\\n' | sed -u 's/\r//g'",
        \   escaped_selection,
        \   g:ollama_model
        \)
    endif

    call s:SetStatus('Processing with Ollama...')
    let output = system(command)

    if v:shell_error
        if v:shell_error == 124
            call s:DisplayError("Request timed out after " . g:ollama_timeout . " seconds")
        else
            call s:DisplayError("Failed to process request (error code: " . v:shell_error . ")")
        endif
        return
    endif

    call RestoreStatusLine()
    call s:OpenCRWindow(output)
endfunction

" Set the status line text
function! s:SetStatus(message)
    " Clear the status line and set the new message
    redraw
    echohl Special
    echon a:message
    echohl None
endfunction

" Public Interface
function! ollama#InstallDependencies()
    if s:HasCommand('ollama')
        call s:SetStatus('Ollama is already installed')
        return 1
    endif
    
    let l:install_choice = confirm('Ollama is not installed. Would you like to install it now?', "&Yes\n&No", 1)
    if l:install_choice != 1
        return 0
    endif
    
    if s:InstallOllama()
        call s:SetStatus('Ollama installed successfully')
        if !s:InstallModel(g:ollama_model)
            call s:DisplayError('Failed to install model ' . g:ollama_model)
            return 0
        endif
        return 1
    endif
    
    return 0
endfunction

" Commands
command! -nargs=0 OllamaInstall call ollama#InstallDependencies()

" Key Mappings
xnoremap <silent> <Leader>l :<C-u>call <SID>ProcessWithOllama('v', 0)<CR>
nnoremap <silent> <Leader>l :call <SID>ProcessWithOllama('n', 0)<CR>
xnoremap <silent> <Leader>L :<C-u>call <SID>ProcessWithOllama('v', 1)<CR>
nnoremap <silent> <Leader>L :call <SID>ProcessWithOllama('n', 1)<CR>
