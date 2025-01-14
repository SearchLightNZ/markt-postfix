#!/usr/bin/env ruby

require 'English'
require 'optparse'
require 'yaml'

options = {
  key: 'postfix::master_services',
}
ARGV.options { |opts|
  @program_name = opts.program_name
  opts.banner = "Usage: #{@program_name} [options] master.cf"
  opts.on('-k', '--key=KEY', "The key to output the values under (default #{options[:key]})") do |key|
    options[:key] = key
  end
}.parse!

raise "You need to specify exactly one file argument, got #{ARGV.length}" unless ARGV.length == 1

unless MatchData.instance_methods.include?(:named_captures)
  # monkey-patch named_captures for Ruby < 2.4
  class MatchData
    def named_captures
      names.map { |n| [n, self[n]] }.to_h
    end
  end
end

new_entry = proc do |h, k| h[k] = Hash.new(&new_entry) end
entries = Hash.new(&new_entry)
cur = nil

IO.foreach(ARGV[0]) do |line|
  case line
  when %r{^#\s*$}, %r{^$}
    # ignore empty lines/comment, reset current entry
    cur = nil
  when %r{^(?<comment>#)?(?<name>\w[\w-]+)\s+(?<type>\w+)\s+(?<private>[yn-])\s+(?<unprivileged>[yn-])\s+(?<chroot>[yn-])\s+(?<wakeup>\S+)\s+(?<process_limit>\S+)\s+(?<command>\S+)\s*$}
    c = $LAST_MATCH_INFO.named_captures
    name = "#{c.delete('name')}/#{c.delete('type')}"
    if entries.include?(name)
      candidate = "#{name} (#{c['command']})"
      i = 0
      while entries.include?(candidate)
        i += 1
        candidate = "#{name} (#{c['command']} duplicate ##{i})"
      end
      STDERR.puts("Entry #{name} already exists, using '#{candidate}'. This is an invalid service name on purpose, please pick which one you want.")
      name = candidate
    end
    c.delete_if { |k, v| ['private', 'unprivileged', 'chroot', 'wakeup', 'process_limit'].include?(k) && (v == '-') }
    cur = entries[name]
    cur['ensure'] = c.delete('comment') ? 'absent' : 'present'
    cur.merge!(c)
  when %r{^(?<comment>#)?\s+(?<args>-o (?<option>\{\s*(?<key>[^=]+?)\s*=(?<value>.*?)\s*\}|(?<key>[^=\s]+)=(?<value>\S*?))|.*?)\s*$}
    c = $LAST_MATCH_INFO.named_captures
    if cur.nil?
      if c['comment'] && !(c['option'])
        # this could as well be a regular comment, ignore...
        next
      end
      STDERR.puts("No current entry to add option to: #{c['option']}")
    elsif c['comment'] && (cur['ensure'] == 'present')
      STDERR.puts("Cannot add commented option/args to enabled service: #{c['args']}")
    elsif !(c['comment']) && (cur['ensure'] == 'absent')
      STDERR.puts("Cannot handle non-commented option/args after commented service: #{c['args']}")
    elsif c['option']
      cur['options'][c['key']] = c['value']
    else
      cur['command'] += " #{c['args']}"
    end
  else
    cur = nil
    STDERR.puts("Unhandled line #{line}")
  end
end

puts ''"
# This file was generated by #{@program_name} on #{Time.now}
#
# ==========================================================================
# service type  private unpriv  chroot  wakeup  maxproc command + args
#               (yes)   (yes)   (no)    (never) (100)
# ==========================================================================
"''
puts YAML.dump(options[:key] => entries)
