" vim: set ts=8 sw=8 noet :

" {{{ Implementation

function! s:LineIterInit()
	let l:ret = {}

	let l:ret.firstline = 1

	normal! G
	let l:ret.lastline = line('.')
	normal! gg

	let l:ret.cur = l:ret.firstline - 1

	return l:ret
endfunction

function! s:LineIterNext(iter)
	let a:iter.cur = a:iter.cur + 1
	if a:iter.cur > a:iter.lastline
		return 0
	endif
	return 1
endfunction

function! s:LineIterCur(iter)
	return a:iter.cur
endfunction

function! s:GetGitFilename(line)
	" diff --git a/foo/bar b/foo/bar
	"              ^^^^^^^
	let l:leader = "diff --git "
	let l:idx = stridx(a:line, l:leader)
	if l:idx == -1
		return ""
	endif

	let l:idx = l:idx + strlen(l:leader)
	let l:front = stridx(a:line, "/", l:idx)
	if l:front == -1
		return ""
	endif

	let l:front = l:front + 1

	let l:back = stridx(a:line, " ", l:front)
	if l:back == -1
		return ""
	endif

	let l:len = l:back - l:front
	let l:fname = strpart(a:line, l:front, l:len)
	return l:fname
endfunction

function! s:GetIndexFilename(line, mode)
	" svn
	" Index: foo/bar
	"        ^^^^^^^
	" quilt
	" Index: a/foo/bar
	"          ^^^^^^^
	let l:leader = "Index: "
	let l:idx = stridx(a:line, l:leader)
	if l:idx == -1
		return ""
	endif

	let l:front = l:idx + strlen(l:leader)

	if a:mode == 'quilt'
		let l:idx = stridx(a:line, '/')
		if l:idx == -1
			return ""
		endif

		let l:front = l:idx + 1
	endif

	let l:fname = strpart(a:line, l:front)
	return l:fname
endfunction

function! s:GetHunkLineNo(line)
	" Line number is number after the plus
	" Examples:
	"   @@ -1231,7 +1231,7 @@
	"   @@ -1411,6 +1411,7 @@ struct foo,
	"   @@ -1 +1 @@
	let l:idx = stridx(a:line, '+')
	if l:idx == -1
		return -1
	endif
	let l:front = l:idx + 1

	let l:back = stridx(a:line, ',', l:front)
	if l:back == -1
		let l:back = stridx(a:line, ' ', l:front)
	endif
	if l:back == -1
		return -1
	endif

	let l:len = l:back - l:front
	let l:lineno = strpart(a:line, l:front, l:len)
	return str2nr(l:lineno)
endfunction

function! s:StartsWith(line, query)
	if stridx(a:line, a:query) == 0
		return 1
	endif
	return 0
endfunction

function! s:AddJumpEntry(fname, lnum, desc)
	let l:entry = {}
	let l:entry.text = a:desc
	let l:entry.filename = a:fname
	let l:entry.lnum = a:lnum
	call setqflist([l:entry], 'a')
endfunction

function! s:AddJumpEntryFromState(state, desc)
	call s:AddJumpEntry(a:state.fname, a:state.lineno, a:desc)
endfunction

function! s:CheckDeleteOnlyHunk(state)
	if a:state.printed == 0 && a:state.lineno > 0
		let a:state.lineno = a:state.lineno - 3
		call s:AddJumpEntryFromState(a:state, "")
	endif
endfunction

function! s:InitState(state)
	let a:state.lineno = 0
	let a:state.plusfound = 0
	let a:state.printed = 0
	let a:state.skip = 0
endfunction

function! s:SetStateNewHunk(state)
	call s:InitState(a:state)
	let a:state.skip = 3
endfunction

function! s:ProcessLine(state, iter)
	let l:line = getline(s:LineIterCur(a:iter))

	if a:state.skip > 0
		let a:state.skip = a:state.skip - 1
	elseif s:StartsWith(l:line, 'diff --git')
		call s:CheckDeleteOnlyHunk(a:state)
		let a:state.fname = s:GetGitFilename(l:line)
		call s:SetStateNewHunk(a:state)
	elseif s:StartsWith(l:line, 'Index: ')
		call s:CheckDeleteOnlyHunk(a:state)
		let a:state.fname = s:GetIndexFilename(l:line, a:state.mode)
		call s:SetStateNewHunk(a:state)
	elseif s:StartsWith(l:line, '@@')
		call s:CheckDeleteOnlyHunk(a:state)
		let a:state.lineno = s:GetHunkLineNo(l:line)
		let a:state.plusfound = 0
	elseif a:state.plusfound == 0 && s:StartsWith(l:line, '+')
		let a:state.plusfound = 1
		let a:state.printed = 1
		let l:toprint = strpart(l:line, 1)
		call s:AddJumpEntryFromState(a:state, l:toprint)
	elseif a:state.plusfound == 0 && s:StartsWith(l:line, '-')
		return
	else
		let a:state.lineno = a:state.lineno + 1
	endif
endfunction

function! s:DiffName(mode)
	if a:mode == "quilt"
		return system("quilt top")
	else
		return a:mode . " diff"
	endif
endfunction

function! s:ProcessDiff(filename, mode)
	let l:state = {}
	call s:InitState(l:state)
	let l:state.mode = a:mode

	call setqflist([], ' ')

	let l:diffname = s:DiffName(a:mode)
	call s:AddJumpEntry(a:filename, 1, l:diffname)

	let l:iter = s:LineIterInit()
	while s:LineIterNext(l:iter)
		call s:ProcessLine(l:state, l:iter)
	endwhile

	call s:CheckDeleteOnlyHunk(l:state)

	copen
endfunction

function! s:IsDir(dir, subdir)
	let l:query = a:dir . '/' . a:subdir
	return isdirectory(l:query)
endfunction

function! s:DetectModeAtDir(dir)
	if     !empty($QUILT_PATCHES) && s:IsDir(a:dir, $QUILT_PATCHES)
		return 'quilt'
	elseif s:IsDir(a:dir, 'patches')
		return 'quilt'
	elseif s:IsDir(a:dir, '.svn')
		return 'svn'
	elseif s:IsDir(a:dir, '.git')
		return 'git'
	endif

	if a:dir == '/'
		return ""
	endif

	let l:parent = simplify(a:dir . '/..')
	return s:DetectModeAtDir(l:parent)
endfunction

function! s:DetectMode(args)
	if empty(a:args)
		return s:DetectModeAtDir(getcwd())
	endif
	if     a:args == 'git'
		return 'git'
	elseif a:args == 'svn' || a:args == 'subversion'
		return 'svn'
	elseif a:args == 'quilt'
		return 'quilt'
	endif
	return ''
endfunction

function! s:PrepareDiffCmd(mode, tmpfile)
	if     a:mode == 'git'
		let l:cmd = 'git diff > ' . a:tmpfile
	elseif a:mode == 'svn'
		let l:cmd = 'svn diff > ' . a:tmpfile
	elseif a:mode == 'quilt'
		let l:cmd = 'quilt diff > ' . a:tmpfile
	else
		return ''
	endif
	return l:cmd
endfunction

function! s:DiffBrowse(args)
	let l:tmpfile = tempname()

	let l:mode = s:DetectMode(a:args)
	let l:cmd = s:PrepareDiffCmd(l:mode, l:tmpfile)
	if empty(l:cmd)
		echoe 'Diff Failed - unrecognized VCS'
		return
	endif

	call system(l:cmd)

	execute ':e' l:tmpfile

	call s:ProcessDiff(l:tmpfile, l:mode)
endfunction

" }}}

" {{{ Interface

command! -nargs=? DiffBrowse call s:DiffBrowse(<q-args>)

" }}}
