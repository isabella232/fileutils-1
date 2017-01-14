#
# Cookbook Name:: fileutils
# Library:: helper
#
# Copyright 2017 Nordstrom, Inc.
#
# All rights reserved - Do Not Redistribute

# Utility methods to change directory and file attributes
module DirChangeHelper
  require 'etc'
  require 'find'

  # Permissions
  R = 0444  # Read
  W = 0222  # Write
  X = 0111  # Search/execute
  SU = 04000 # Assign user
  SG = 02000 # Assign group
  T = 01000  # Sticky bit

  # Who
  U = 07700  # Owning user
  G = 07070  # Owning group
  O = 07007  # Others
  A = 07777  # Everyone

  def update_files(path, pattern, recursive, follow_symlink,
                   directory_mode, file_mode, group, owner,
                   only_files, only_directories, why_run
                  )
    @path = path
    @pattern = pattern
    @recursive = recursive
    @follow_symlink = follow_symlink
    @directory_mode = directory_mode
    @file_mode = file_mode
    @group = group
    @owner = owner
    @why_run = why_run
    @only_files = only_files
    @only_directories = only_directories
    @uid = new_uid
    @gid = new_gid
    @changed = false
    find_and_update_files(@path)
    @changed
  end

  def find_and_update_files(path)
    if ::File.directory?(path) && @recursive
      ::Find.find(path) do |node|
        update(node)
      end
    else
      update(path)
    end
  end

  def update(path)
    raise "Tried to update root /" if path == '/'
    return if @pattern && ::File.basename(path) !~ @pattern
    fs = ::File.lstat(path)
    case
    when fs.directory? && ! @only_files
      mode = new_mode(fs.mode, @directory_mode)
      file_update(path, mode) if file_check(fs, mode)
    when fs.file? && ! @only_directories
      mode = new_mode(fs.mode, @file_mode)
      file_update(path, mode) if file_check(fs, mode)
    when fs.symlink?
      ::Find.prune unless @follow_symlink
      find_and_update_files(::File.readlink(path))
    end
  end

  def file_update(path, mode)
    Chef::Log.info("Path #{path} updated mode #{mode} owner #{@uid} group #{@gid}")
    @changed = true
    return if @why_run
    f = ::File.new(path)
    f.chmod(mode)
    f.chown(@uid, @gid)
  end

  def file_check(fs, mode)
    change = false
    change = true unless fs.mode == new_mode(fs.mode, mode)
    change = true unless fs.uid == @uid
    change = true unless fs.gid == @gid
    change
  end

  def new_mode(mode, settings)
    calc_mode = mode
    [settings].flatten.compact.each do |setting|
      calc_mode = case setting
                  when /\+/
                    calc_mode | mode_mask(setting)
                  when /-/
                    calc_mode & ~mode_mask(setting)
                  else
                    setting
                  end
    end
    calc_mode
  end

  def mode_mask(setting)
    who_mask(setting) & prm_mask(setting)
  end

  def new_uid
    Etc.getpwnam(@owner).uid
  end

  def new_gid
    Etc.getgrnam(@group).gid
  end

  def who_mask(setting)
    who = 0
    who |= U | G | O if setting =~ /^(\+|-|a)/
    who |= U if setting =~ /u/
    who |= G if setting =~ /g/
    who |= O if setting =~ /o/
    who
  end

  def prm_mask(setting)
    access = 0
    access |= R if setting =~ /r/
    access |= W if setting =~ /w/
    access |= X if setting =~ /x/
    access |= T if setting =~ /t/
    access |= SU if setting =~ /s.*u/
    access |= SG if setting =~ /s.*g/
    access
  end
end
