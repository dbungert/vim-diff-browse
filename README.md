# vim-diff-browse
Populate the vim jumplist based on the uncommitted differences from git, svn,
or quilt.

# Usage
* In the root directory of a sandbox, run

  `vim "+:DiffBrowse <vcs>"`

  where vcs is git, svn, or quilt
* Or, just run

  `vim "+:DiffBrowse"`

  and detection will occur to determine if git/svn/quilt logic should be used.
  If quilt and a VCS are both present, quilt will take precedence.
* vim will launch with one entry in the jumplist per hunk present in the diff
  output.

# Known Issues
- [ ] launch with an empty diff is handled poorly
- [ ] if the editor is not launched from the root of the VCS sandbox, jumping
      to files doesn't always work correctly
