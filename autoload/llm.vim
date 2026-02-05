" Helper: Custom JSON encoding using Vim's built-in json_encode()
function! llm#encode(obj) abort
  return json_encode(a:obj)
endfunction

" Helper: Open or reuse a global scratch buffer for LLM responses
function! llm#open_scratch_buffer() abort
  " If our scratch buffer (LLM history) already exists...
  if exists('g:llm_scratch_bufnr')
    " If the buffer happens to be loaded, try to bring it into view.
    if bufloaded(g:llm_scratch_bufnr)
      " Check if it's visible in any window.
      for win in range(1, winnr('$'))
        if winbufnr(win) == g:llm_scratch_bufnr
          execute win . "wincmd w"
          return g:llm_scratch_bufnr
        endif
      endfor
      " Not visible? Open it in a vertical split.
      execute 'vertical sbuffer ' . g:llm_scratch_bufnr
      return g:llm_scratch_bufnr
    endif
  endif

  " Otherwise, create a new scratch buffer in a vertical split.
  execute 'vertical new'
  enew
  setlocal buftype=nofile
  setlocal bufhidden=hide
  setlocal noswapfile
  setlocal nobuflisted
  file [LLM-Scratch]
  
  " Add syntax highlighting for the LLM chat
  if !exists("b:llm_syntax_loaded")
    syntax clear
    syntax match LLMPromptHeader /^Prompt: .*$/
    syntax match LLMTimestamp /^==== .*====$/
    syntax region LLMPrompt start=/^Prompt: / end=/^$/ contains=LLMPromptHeader
    syntax region LLMResponse start=/^Response:/ end=/^\s*$/ contains=LLMResponseHeader
    syntax match LLMResponseHeader /^Response:$/
    
    highlight LLMPromptHeader ctermfg=green guifg=green
    highlight LLMPrompt ctermfg=cyan guifg=cyan
    highlight LLMResponseHeader ctermfg=yellow guifg=yellow
    highlight LLMResponse ctermfg=white guifg=white
    highlight LLMTimestamp ctermfg=magenta guifg=magenta
    
    let b:llm_syntax_loaded = 1
  endif
  
  let g:llm_scratch_bufnr = bufnr('%')
  return g:llm_scratch_bufnr
endfunction

" Functions for the Snippet Scratch Buffer (for context snippets)

" Open or reuse the snippet scratch buffer
function! llm#open_snippet_buffer() abort
  if exists('g:llm_snippet_bufnr')
    if bufloaded(g:llm_snippet_bufnr)
      " If visible, bring to focus; otherwise, open in a vertical split.
      for win in range(1, winnr('$'))
        if winbufnr(win) == g:llm_snippet_bufnr
          execute win . "wincmd w"
          return g:llm_snippet_bufnr
        endif
      endfor
      execute 'vertical sbuffer ' . g:llm_snippet_bufnr
      return g:llm_snippet_bufnr
    endif
  endif
  execute 'vertical new'
  enew
  setlocal buftype=nofile
  setlocal bufhidden=hide
  setlocal noswapfile
  setlocal nobuflisted
  file [LLM-Snippets]
  let g:llm_snippet_bufnr = bufnr('%')
  return g:llm_snippet_bufnr
endfunction

" Clear the snippet scratch buffer explicitly
function! llm#clear_snippet_buffer() abort
  if exists('g:llm_snippet_bufnr') && bufexists(g:llm_snippet_bufnr)
    call setbufline(g:llm_snippet_bufnr, 1, [])
    echo "[LLM-Snippets] cleared."
  else
    echo "No snippet buffer exists."
  endif
endfunction

" Add a snippet from the current visual selection to the snippet scratch buffer -- storing only filename and start,end meta info
function! llm#add_snippet() abort
  " Get the current buffer's filename
  let l:filename = bufname('%')
  if l:filename == ""
    let l:filename = "[No Name]"
  endif

  " Get the visual selection's start and end line numbers
  let l:start = getpos("'<")[1]
  let l:end   = getpos("'>")[1]

  " Construct an entry in the form: filename: start,end (only meta info)
  let l:entry = l:filename . ": " . l:start . "," . l:end

  " Open (or create) the snippet scratch buffer and append the entry
  let l:bufnr = llm#open_snippet_buffer()
  call append(line('$'), l:entry)
  echo "Snippet meta info added for " . l:filename
endfunction

" Helper: Get buffer content, using snippets if available
function! llm#get_buffer_content(bufnr, filename) abort
  " Default to full buffer content
  let l:contents = join(getbufline(a:bufnr, 1, '$'), "\n")
  
  " If the snippet buffer exists, check for override entries for this file
  if exists('g:llm_snippet_bufnr') && bufexists(g:llm_snippet_bufnr)
    let l:snip_lines = getbufline(g:llm_snippet_bufnr, 1, '$')
    let l:found_snippets = []
    
    " First pass: collect all snippets for this file
    for l:snip in l:snip_lines
      if l:snip =~ '^' . escape(a:filename, '\\') . ':\s'
        " Expected format: filename: start,end
        let l:parts = split(l:snip, ':\s\+')
        if len(l:parts) >= 2
          let l:meta = l:parts[1]
          let l:range = split(l:meta, ',')
          if len(l:range) == 2
            let l:snip_start = str2nr(l:range[0])
            let l:snip_end   = str2nr(l:range[1])
            " Store snippet info for later processing
            call add(l:found_snippets, {'start': l:snip_start, 'end': l:snip_end})
          endif
        endif
      endif
    endfor
    
    " If we found snippets, replace contents with concatenated snippets
    if !empty(l:found_snippets)
      let l:snippets_content = []
      for l:snippet in l:found_snippets
        let l:snippet_text = join(getbufline(a:bufnr, l:snippet.start, l:snippet.end), "\n")
        let l:snippet_header = "--- Snippet from lines " . l:snippet.start . "-" . l:snippet.end . " ---"
        call add(l:snippets_content, l:snippet_header)
        call add(l:snippets_content, l:snippet_text)
      endfor
      " Join all snippets with newlines and a separator
      let l:contents = join(l:snippets_content, "\n\n")
    endif
  endif
  
  return l:contents
endfunction

" Process text with an external LLM tool using the current adapter
function! llm#process(json_filename, prompt, model) abort
  " Get the current adapter
  let l:adapter = llm#adapter#get_current()
  
  " Use the adapter to process the request
  return l:adapter.process(a:json_filename, a:prompt, a:model)
endfunction

" Function to get the list of available models from the current adapter
function! llm#get_available_models() abort
  " Get the current adapter
  let l:adapter = llm#adapter#get_current()
  
  " Use the adapter to get available models
  return l:adapter.get_available_models()
endfunction

" Function to set the default model
function! llm#set_default_model(model) abort
  let g:llm_default_model = a:model
endfunction

" Function to set the default adapter
function! llm#set_default_adapter(adapter) abort
  let g:llm_default_adapter = a:adapter
  call llm#adapter#set_current(a:adapter)
endfunction

" Function to handle LLM queries with attached files
function! llm#run_with_files(...) abort
  " Arguments: file1, file2, ..., [--], [prompt]
  " Parse arguments to separate files from optional prompt
  
  let l:files = []
  let l:prompt = ''
  let l:found_delimiter = 0
  
  " Iterate through all arguments
  for l:arg in a:000
    if l:arg == '--'
      " Delimiter found - everything after is the prompt
      let l:found_delimiter = 1
      continue
    endif
    
    if l:found_delimiter
      " Build prompt from remaining arguments
      if l:prompt == ''
        let l:prompt = l:arg
      else
        let l:prompt .= ' ' . l:arg
      endif
    else
      " Before delimiter - treat as file path
      let l:expanded = expand(l:arg)
      let l:fullpath = fnamemodify(l:expanded, ':p')
      
      " Validate file or directory exists
      if filereadable(l:fullpath) || isdirectory(l:fullpath)
        call add(l:files, l:fullpath)
      else
        echoerr "LLMFile: File not found or not readable: " . l:arg
        return
      endif
    endif
  endfor
  
  " Check if at least one file was provided
  if empty(l:files)
    echoerr "LLMFile: No valid files provided"
    return
  endif
  
  " Display confirmation of attached files
  echo "LLMFile: Attaching " . len(l:files) . " file(s): " . join(l:files, ', ')
  
  " Call main LLM function with file list
  call llm#run(l:prompt, 0, l:files)
endfunction

" Main LLM function that gathers context and processes input
function! llm#run(...) abort
  " Optional prompt argument; if supplied, this is the extra user prompt.
  let l:prompt = (a:0 >= 1 ? a:1 : '')
  " Optional model argument; if supplied, this is a boolean to choose the model.
  let l:choose_model = (a:0 >= 2 ? a:2 : 0)
  " Optional file list argument; if supplied, these are files to attach.
  let l:file_list = (a:0 >= 3 ? a:3 : [])
  let l:model = ''
  if l:choose_model
    let l:models = llm#get_available_models()
    echo "Choose a model:"
    for i in range(len(l:models))
      echo i + 1 . ". " . l:models[i]
    endfor
    let l:choice = input("Enter the model number: ")
    let l:model = l:models[l:choice - 1]
    call llm#set_default_model(l:model)
  endif

  " Get the current window's cursor location.
  let l:cursor_line = line('.')
  let l:cursor_col  = col('.')

  " Get a list of buffer numbers in the current tab.
  let l:buf_list = tabpagebuflist(tabpagenr())

  " Get the currently active buffer number.
  let l:active_bufnr = bufnr('%')

  " Build a list for buffers' information, skipping:
  "   a) the active buffer (stored separately)
  "   b) the scratch buffer (the llm_history, which is added separately)
  "   c) the snippet buffer
  let l:buffers = []
  for l:bufnr in l:buf_list
    if l:bufnr == l:active_bufnr
      continue
    endif
    if (exists('g:llm_scratch_bufnr') && l:bufnr == g:llm_scratch_bufnr) || (exists('g:llm_snippet_bufnr') && l:bufnr == g:llm_snippet_bufnr)
      continue
    endif
    let l:filename = bufname(l:bufnr)
    if empty(l:filename)
      let l:filename = "[No Name]"
    endif
    let l:contents = llm#get_buffer_content(l:bufnr, l:filename)
    call add(l:buffers, {'filename': l:filename, 'contents': l:contents})
  endfor

  " Gather details for the active buffer.
  let l:active_filename = bufname(l:active_bufnr)
  let l:active_contents = llm#get_buffer_content(l:active_bufnr, l:active_filename)

  " Assemble the data dictionary.
  let l:data = {
        \ 'cursor_line': l:cursor_line,
        \ 'cursor_col':  l:cursor_col,
        \ 'buffers':     l:buffers,
        \ 'active_buffer': {
        \      'filename': l:active_filename,
        \      'contents': l:active_contents,
        \ },
        \ }

  " Include the prompt if provided.
  if l:prompt != ''
    let l:data.prompt = l:prompt
  endif
  
  " Include file arguments if provided
  if !empty(l:file_list)
    let l:data.file_arguments = l:file_list
  endif

  " Always add the scratch buffer's contents as llm_history if it exists
  if exists('g:llm_scratch_bufnr')
    let l:history = join(getbufline(g:llm_scratch_bufnr, 1, '$'), "\n")
    let l:data.llm_history = l:history
  endif

  " Convert the data dictionary to JSON.
  let l:json_data = llm#encode(l:data)

  " Write the JSON data to a temporary file.
  let l:tempfile = tempname()
  call writefile(split(l:json_data, "\n"), l:tempfile)

  " Call the external LLM agent function using the temporary file and prompt.
  let l:response = llm#process(l:tempfile, l:prompt, l:model)

  " Open (or reuse) the scratch buffer and switch to it.
  let l:scratch_buf = llm#open_scratch_buffer()
  execute 'buffer ' . l:scratch_buf

  " Append a header with the current timestamp.
  let l:last_line = line('$')
  call append(l:last_line, '==== ' . strftime("%c") . ' ====')

  " Immediately after the timestamp, append the prompt if provided.
  if l:prompt != ''
    call append(l:last_line + 1, 'Prompt: ' . l:prompt)
    let l:last_line += 1
  endif

  " Append the LLM response line by line.
  for l:line in split(l:response, "\n")
    call append(l:last_line + 1, l:line)
    let l:last_line += 1
  endfor

  " Append a blank line after the entry.
  call append(l:last_line + 1, '')

  " Scroll to the bottom of the scratch buffer.
  execute 'normal! G'
 
  " Return focus to the previous window.
  wincmd p
endfunction

" Ensure session directory exists
function! llm#ensure_session_dir() abort
  let l:session_dir = expand('~/.vim/vim-llm-assistant/sessions')
  if !isdirectory(l:session_dir)
    call mkdir(l:session_dir, 'p')
  endif
  return l:session_dir
endfunction

" List available session files for completion
function! llm#complete_sessions(arglead, cmdline, cursorpos) abort
  let l:session_dir = llm#ensure_session_dir()
  let l:files = readdir(l:session_dir)
  return filter(l:files, 'v:val =~ ''^'' . a:arglead')
endfunction

" Save current LLM session including history, snippets, and tab layout
function! llm#save_session(filename) abort
  " Get session directory
  let l:session_dir = llm#ensure_session_dir()
  
  " If no filename provided, prompt for one
  let l:filename = a:filename
  if l:filename == ""
    let l:filename = input('Enter filename to save LLM session: ')
    if l:filename == ""
      echo "No filename provided, aborting session save."
      return
    endif
  endif
  
  " Ensure filename has .json extension
  if l:filename !~ '\.json$'
    let l:filename .= '.json'
  endif
  
  " If not absolute path, prepend session directory
  if l:filename !~ '^/'
    let l:filepath = l:session_dir . '/' . l:filename
  else
    let l:filepath = l:filename
  endif
  
  " Build session dictionary
  let l:session = {}
  
  " Save history buffer content if it exists
  let l:history_bufnr = bufnr('[LLM-Scratch]')
  if l:history_bufnr != -1
    let l:session.history = getbufline(l:history_bufnr, 1, '$')
  else
    let l:session.history = []
  endif
  
  " Save snippet buffer content if it exists
  let l:snippet_bufnr = bufnr('[LLM-Snippets]')
  if l:snippet_bufnr != -1
    let l:session.snippets = getbufline(l:snippet_bufnr, 1, '$')
  else
    let l:session.snippets = []
  endif
  
  " Collect all visible files across all tabs
  let l:session.visible_files = []
  for l:tab in gettabinfo()
    for l:winid in l:tab.windows
      call win_execute(l:winid, 'let g:llm_temp_fname = expand("%:p")')
      if g:llm_temp_fname != ""
        " Handle special buffers - store just the name for LLM-Scratch and LLM-Snippets
        let l:fname_to_store = g:llm_temp_fname
        if g:llm_temp_fname =~ '\[LLM-\(Scratch\|Snippets\)\]$'
          let l:fname_to_store = fnamemodify(g:llm_temp_fname, ':t')
        endif
        if index(l:session.visible_files, l:fname_to_store) == -1
          call add(l:session.visible_files, l:fname_to_store)
        endif
      endif
    endfor
  endfor
  
  " Save tab and window layout
  let l:session.tabs = []
  for l:tab in gettabinfo()
    let l:tab_entry = {}
    let l:tab_entry.windows = []
    for l:winid in l:tab.windows
      call win_execute(l:winid, 'let g:llm_temp_fname = expand("%:p")')
      if g:llm_temp_fname != "" 
        " Handle special buffers - store just the name for LLM-Scratch and LLM-Snippets
        let l:fname_to_store = g:llm_temp_fname
        if g:llm_temp_fname =~ '\[LLM-\(Scratch\|Snippets\)\]$'
          let l:fname_to_store = fnamemodify(g:llm_temp_fname, ':t')
        endif

        call add(l:tab_entry.windows, l:fname_to_store)
      endif
    endfor
    call add(l:session.tabs, l:tab_entry)
  endfor
  
  " Save to file
  let l:json = json_encode(l:session)
  call writefile(split(l:json, "\n"), l:filepath)
  echo "LLM session saved to " . l:filepath
endfunction

" Load LLM session from file
function! llm#load_session(filename) abort
  " Get session directory
  let l:session_dir = llm#ensure_session_dir()
  
  " If no filename provided, abort
  if a:filename == ""
    echo "No filename provided, aborting session load."
    return
  endif
  
  " If not absolute path, prepend session directory
  if a:filename !~ '^/'
    let l:filepath = l:session_dir . '/' . a:filename
    if !filereadable(l:filepath) && filereadable(l:session_dir . '/' . a:filename . '.json')
      let l:filepath .= '.json'
    endif
  else
    let l:filepath = a:filename
  endif
  
  " Check if file exists
  if !filereadable(l:filepath)
    echoerr "Session file " . l:filepath . " not found!"
    return
  endif
  
  " Read and decode the JSON file
  let l:lines = readfile(l:filepath)
  let l:session = json_decode(join(l:lines, "\n"))
  
  " Create or populate the history buffer
  if has_key(l:session, 'history') && !empty(l:session.history)
    let l:history_bufnr = llm#open_scratch_buffer()
    call setbufvar(l:history_bufnr, '&buftype', 'nofile')
    call setbufvar(l:history_bufnr, '&swapfile', 0)
    
    " Clear and populate the buffer
    call deletebufline(l:history_bufnr, 1, '$')
    call setbufline(l:history_bufnr, 1, l:session.history)
    call setbufvar(l:history_bufnr, '&modified', 0)
  endif
  
  " Create or populate the snippet buffer
  if has_key(l:session, 'snippets') && !empty(l:session.snippets)
    let l:snippet_bufnr = llm#open_snippet_buffer()
    call setbufvar(l:snippet_bufnr, '&buftype', 'nofile')
    call setbufvar(l:snippet_bufnr, '&swapfile', 0)
    
    " Clear and populate the buffer
    call deletebufline(l:snippet_bufnr, 1, '$')
    call setbufline(l:snippet_bufnr, 1, l:session.snippets)
    call setbufvar(l:snippet_bufnr, '&modified', 0)
  endif
  
  " Add all visible files to the argument list
  if has_key(l:session, 'visible_files') && !empty(l:session.visible_files)
    " Add all files to the argument list (without clearing first)
    for l:file in l:session.visible_files
      execute 'argadd ' . fnameescape(l:file)
    endfor
  endif
  
  " Restore the tab and window layout
  if has_key(l:session, 'tabs')
    " Close all current tabs
    silent! tabonly
    
    " Open each tab and its windows
    let l:tindex = 0
    for l:tab in l:session.tabs
      if l:tindex > 0
        tabnew
      endif
      
      let l:windex = 0
      for l:file in l:tab.windows
        if l:windex == 0
          " Special handling for LLM buffers
          if l:file == '[LLM-Scratch]'
            call llm#open_scratch_buffer()
          elseif l:file == '[LLM-Snippets]'
            call llm#open_snippet_buffer()
          else
            execute 'edit ' . fnameescape(l:file)
          endif
        else
          execute 'vsplit ' . fnameescape(l:file)
        endif
        let l:windex += 1
      endfor
      let l:tindex += 1
    endfor
  endif
  
  echo "LLM session loaded from " . l:filepath
endfunction