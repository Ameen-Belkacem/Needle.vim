
let g:sbUpdate = 300

function! s:getBufferNumber()
    return bufnr("%")
endfunction

function! s:getLinesCount()
    return line('$')
endfunction

function! s:getTopVisibleLine()
    return line('w0')
endfunction

function! s:getBottomVisibleLine()
    return line('w$')
endfunction

function! s:initScrollbar()
    augroup ScrollBarGroup
        autocmd BufEnter     * :call <sid>showScrollbar()
        autocmd BufWinEnter  * :call <sid>showScrollbar()
        autocmd FocusGained  * :call <sid>showScrollbar()
        autocmd CursorMoved  * :call <sid>showScrollbar()
        autocmd VimResized   * :call <sid>showScrollbar()
    augroup END

    if !exists('g:scrollbarFG')
        let g:scrollbarFG = '|'
    endif

    exec "sign define sbFG text=".g:scrollbarFG." texthl=ScrollbarFG"
endfunction

function! s:isScrollbarNeeded()
     if (winheight(0) >= s:getLinesCount()) ||
        \ (exists('b:bufferTop') && b:bufferTop == s:getTopVisibleLine())
        return 0
    endif 
    return 1
endfunction

function! s:showScrollbar()
    if !s:isScrollbarNeeded()
        return 
    endif

    let bufferSize = s:getLinesCount()
    let buffer = s:getBufferNumber()
    let topLine = s:getTopVisibleLine()
    let bottomLine = s:getBottomVisibleLine()

    let pageLines = bottomLine - topLine
    let pageTop = str2float(topLine) / bufferSize
    let sbSize = ((pageLines * pageLines) / bufferSize) + 1
    let paddingTop = float2nr(pageTop * pageLines)

    call s:drawScrollbar(topLine, paddingTop, buffer, sbSize, bufferSize)
endfunction

function! s:firstLoad()
     return !exists('b:sbLoaded')
endfunction

function! s:bufferChanged(bufferSize)
    return exists('b:bufferSize') && b:bufferSize != a:bufferSize
endfunction

function! s:cursorJumped(paddingTop, topLine)
    return (a:paddingTop != b:lastPaddingTop) && 
        \ (a:topLine > b:lastTopline + 1 || a:topLine < b:lastTopline - 1)
endfunction

function! s:cursorWalked(topLine)
    return (a:topLine == b:lastTopline + 1 || a:topLine == b:lastTopline - 1)
endfunction

function! s:unplaceSigns(sbTop, sbBottom, buffer)
    if a:sbTop < a:sbBottom 
        for i in range(a:sbTop, a:sbBottom)
            exec ":sign unplace ".i." buffer=".a:buffer
        endfor
    else 
        for i in range(a:sbBottom, a:sbTop)
            exec ":sign unplace ".i." buffer=".a:buffer
        endfor
    endif
endfunction

function! s:placeSigns(sbTop, sbBottom, buffer)
    for i in range(a:sbTop, a:sbBottom) 
        exec ":sign place ".i." line=".i." name=sbFG buffer=".a:buffer
    endfor
endfunction

function! s:tooFastRedraw()
    return exists("b:lastTime") && 
        \ str2float(reltimestr(reltime(b:lastTime))) < (str2float(g:sbUpdate) / 1000)
endfunction

function! s:getSignsOutput(buffer)
    let cmdOutput = ""
    redir => cmdOutput
    silent execute ":sign place buffer=".a:buffer
    redir END
    return cmdOutput
endfunction

function! s:getPlacedSigns(buffer)
    let cmdOutput = s:getSignsOutput(a:buffer)
    let pattern = 'line=\(\d\+\)\s\+id=\(\d\+\)\s\+name=sbFG'
    let placedSigns = []
    while match(cmdOutput, pattern) != -1
        let match = matchlist(cmdOutput, pattern)
        call add(placedSigns, {'line':match[1], 'id':match[2]})
        let cmdOutput = substitute(cmdOutput, pattern, "", "")
    endwhile
    return placedSigns
endfunction

function! s:isBroken(buffer, lastIndex)
    let cmdOutput = s:getSignsOutput(a:buffer)
    let pattern = 'line=\(\d\+\)\s\+id='.a:lastIndex.'\s\+name=sbFG'
    let match = matchlist(cmdOutput, pattern)
    if match[1] != a:lastIndex
        return 1
    endif
    return 0
endfunction

function! s:sbBroken(sbTop, sbBottom, bufferSize, buffer)
    let placedSigns = s:getPlacedSigns(a:buffer)
    if s:bufferChanged(a:bufferSize)
        for i in placedSigns
            if i['line'] != i['id']
                return 1
            endif    
        endfor
    endif    
    return 0
endfunction

function! s:repairRedraw(sbTop, sbBottom, buffer)
    let placedSigns = s:getPlacedSigns(a:buffer)
    for i in placedSigns
        if i['line'] != i['id']
            call s:unplaceSigns(i['id'], i['id'], a:buffer)
            call s:placeSigns(i['id'], i['id'], a:buffer)
        endif    
    endfor
endfunction

function! s:partialRedraw(sbTop, sbBottom, buffer)
    if a:sbTop > b:sbTop
        call s:unplaceSigns(b:sbTop, a:sbTop - 1, a:buffer)
    elseif a:sbTop < b:sbTop
        call s:placeSigns(a:sbTop, b:sbTop - 1, a:buffer)
    endif
    if a:sbBottom > b:sbBottom
        call s:placeSigns(b:sbBottom + 1, a:sbBottom, a:buffer)
    elseif a:sbBottom < b:sbBottom 
        call s:unplaceSigns(a:sbBottom + 1, b:sbBottom, a:buffer)
    endif
endfunction

function! s:fullRedraw(sbTop, sbBottom, buffer)
    call s:placeSigns(a:sbTop, a:sbBottom, a:buffer)
    if exists("b:sbTop") && exists("b:sbBottom") && 
        \ b:sbTop != a:sbTop && b:sbBottom != a:sbBottom
        call s:unplaceSigns(b:sbTop, b:sbBottom + 1, a:buffer)
    endif
endfunction

function! s:isOverlapping(sbTop, sbBottom)
    if exists("b:sbTop") && exists("b:sbBottom")
        return (a:sbTop >= b:sbTop && a:sbTop <= b:sbBottom) 
            \ || (a:sbTop <= b:sbTop && a:sbBottom >= b:sbTop)
    endif
    return 0
endfunction

function! s:drawScrollbar(topLine, paddingTop, buffer, sbSize, bufferSize)
    if s:firstLoad() || s:bufferChanged(a:bufferSize) || 
        \ s:cursorJumped(a:paddingTop, a:topLine) || s:cursorWalked(a:topLine)
        if s:tooFastRedraw() && !s:cursorWalked(a:topLine) && !s:bufferChanged(a:bufferSize)
            return
        endif

        let sbTop = a:topLine + a:paddingTop
        let sbBottom = sbTop + a:sbSize

        if s:bufferChanged(a:bufferSize)
            if s:isBroken(a:buffer, b:sbBottom)
                call s:repairRedraw(sbTop, sbBottom, a:buffer)
            endif
            call s:fullRedraw(sbTop, sbBottom, a:buffer)
        elseif s:isOverlapping(sbTop, sbBottom)
            call s:partialRedraw(sbTop, sbBottom, a:buffer)
        else 
            call s:fullRedraw(sbTop, sbBottom, a:buffer)
        endif

        if !exists("b:sbLoaded")
            let b:sbLoaded =  1
        endif

        let b:lastTopline = a:topLine
        let b:lastPaddingTop = a:paddingTop
        let b:bufferSize = a:bufferSize
        let b:sbTop = sbTop
        let b:sbBottom = sbBottom
        let b:lastTime = reltime()
    endif
endfunction 

call s:initScrollbar()

hi ScrollbarFG ctermfg=green ctermbg=black guifg=#A4A4A4 guibg=#282a36  cterm=none
hi ScrollbarBG ctermfg=darkgreen ctermbg=darkgreen guifg=#282a36 guibg=#282a36  cterm=reverse

hi SignColumn ctermfg=246 ctermbg=235 cterm=NONE guifg=#909194 guibg=#282a36 gui=NONE
hi FlastColmun ctermfg=246 ctermbg=235 cterm=NONE guifg=#909194 guibg=#282a36 gui=NONE