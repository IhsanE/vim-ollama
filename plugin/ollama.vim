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
let g:ollama_max_tokens = get(g:, 'ollama_max_tokens', 2000)
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
    return executable(a:cmd)
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

function! s:OpenCRWindow()
    call s:EnsureCRWindow()
    
    let win_nr = bufwinnr(g:ollama_cr_window)
    if win_nr != -1
        execute win_nr . 'wincmd w'
        return
    endif
    
    execute g:ollama_window_position g:ollama_window_size . 'new' g:ollama_cr_window
    setlocal buftype=nofile
    setlocal bufhidden=hide
    setlocal noswapfile
    setlocal nobuflisted
    setlocal filetype=markdown
    setlocal wrap
    setlocal linebreak
    setlocal nonumber
    
    if !exists('g:ollama_no_syntax')
        syntax enable
        set syntax=markdown
    endif
    
    wincmd p
endfunction

function! s:EscapeInput(input)
    let escaped = substitute(a:input, "'", "'\"'\"'", "g")
    let escaped = substitute(escaped, '"', '\\"', "g")
    let escaped = substitute(escaped, '`', '\\`', "g")
    let escaped = substitute(escaped, '\$', '\\$', "g")
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
    let command = ''
    
    if a:with_question
        let prompt = input('Enter your question: ')
        if empty(prompt)
            call s:DisplayError("Question required")
            return
        endif
        let escaped_prompt = s:EscapeInput(prompt)
        let command = printf(
        \   "echo '%s\nQuestion: %s' | timeout %d ollama run %s --max-tokens %d 2>/dev/null",
        \   escaped_selection,
        \   escaped_prompt,
        \   g:ollama_timeout,
        \   g:ollama_model,
        \   g:ollama_max_tokens
        \)
    else
        let command = printf(
        \   "echo '%s' | timeout %d ollama run %s --max-tokens %d 2>/dev/null",
        \   escaped_selection,
        \   g:ollama_timeout,
        \   g:ollama_model,
        \   g:ollama_max_tokens
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
    
    call s:OpenCRWindow()
    let current_window = winnr()
    execute bufwinnr(g:ollama_cr_window) . 'wincmd w'
    
    silent! normal! ggdG
    call setline(1, split(output, "\n"))
    normal! gg
    
    execute current_window . 'wincmd w'
    call s:SetStatus('Done')
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
