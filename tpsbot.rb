require "rubygems"
require "cinch"
require "date"
require "time"
require "sequel"
require "optparse"

class TaskLogger
    def initialize(filename)
        @db = Sequel.sqlite(filename)
        unless @db.table_exists?(:tasklog)
            @db.create_table :tasklog do
                primary_key :id
                String      :nick
                DateTime    :date
                String      :message
            end
        end
    end

    def add(nick, message, date=DateTime.parse(Time.now.to_s))
        tasks = @db[:tasklog]
        task_id = @db[:tasklog].insert(:nick=>nick, :date=>date, :message=>message)
        "added task: #{task_id} for #{nick}"
    end

    def remove(nick, task_id)
        task = @db[:tasklog].where(:id=>task_id, :nick=>nick).first()
        if task
            task.delete
            "removed #{task_id} for #{nick}"
        else
            "task #{task_id} not found for #{nick}"
        end
    end

    def list(nick, start_date=(DateTime.now - 7), end_date=(DateTime.now))
        tasks = ""
        @db[:tasklog].where(:nick => nick, :date =>start_date..end_date).order_by(:date).each{ |r|
            tasks += "#{r[:id]} #{r[:date].strftime("%Y-%m-%d")} #{r[:message]}\n"
        }
        tasks.length > 0 ? tasks : "No reults"
    end

    def query(q, nick, start_date=(DateTime.now - 7), end_date=(DateTime.now))
        tasks = ""
        @db[:tasklog].where(:nick => nick, :date =>start_date..end_date).order_by.each{ |r|
            if /#{q}/ =~ r[:message].to_s
                tasks += "#{r[:id]} #{r[:date].strftime("%Y-%m-%d")} #{r[:message]}\n"
            end
        }
        tasks.length > 0 ? tasks : "No reults"
    end

end

class TaskLog
    def initialize(tasks)
        @options = {}
        @tasks = tasks
        @parser = OptionParser.new do |opts|
            opts.banner = "!log [options] <task>"
            opts.on("-d", "--date YYYY-MM-DD", "Date to record this task (default now)") do |d|
                @options[:date] = DateTime.parse(d)
            end
        end
    end
    def run(user, args)
        begin
            @options = {}
            @options[:date] = DateTime.now
            @parser.parse!(args)
            @tasks.add(user, args.join(" "), @options[:date])
        rescue
            "ERROR - You're doing it wrong!\n" + usage()
        end
    end
    def usage()
        "\nLog a task:\n" + @parser.to_s
    end
end

class TaskList
    def initialize(tasks)
        @options = {}
        @tasks = tasks
        @parser = OptionParser.new do |opts|
            opts.banner = "!ls [options]"
            opts.on("-s", "--start YYYY-MM-DD", "Limit results to those after this date (default 7 days ago)") do |d|
                @options[:start] = DateTime.parse(d)
            end
            opts.on("-e", "--end YYYY-MM-DD", "Limit results to those before this date (default now)") do |d|
                @options[:end] = DateTime.parse(d)
            end
        end
    end
    def run(user, args)
        begin
            @options = {}
            @options[:end] = DateTime.now
            @options[:start] = @options[:end] - 7
            @parser.parse!(args)
            @tasks.list(user, @options[:start], @options[:end])
        rescue
            "ERROR- Staaaaph! RTFM..\n" + usage()
        end
    end
    def usage()
        "\nList tasks:\n" + @parser.to_s
    end
end

class TaskRemove
    def initialize(tasks)
        @tasks = tasks
    end
    def run(user, args)
        @tasks.remove(user, args.join(" "))
    end
    def usage()
        "\nRemove a task by task ID:\n!rm <task-id>"
    end
end

class TaskQuery
    def initialize(tasks)
        @options = {}
        @tasks = tasks
        @parser = OptionParser.new do |opts|
            opts.banner = "!q [options] <query>"
            opts.on("-s", "--start YYYY-MM-DD", "Limit results to those after this date (default 7 days ago)") do |d|
                @options[:start] = DateTime.parse(d)
            end
            opts.on("-e", "--end YYYY-MM-DD", "Limit results to those before this date (default now)") do |d|
                @options[:end] = DateTime.parse(d)
            end
            opts.on("-n", "--nick NICK", "Query applies to this user (default you)") do |n|
                @options[:nick] = n
            end
        end
    end
    def run(user, args)

        begin
            @options = {}
            @options[:end] = DateTime.now
            @options[:start] = @options[:end] - 7
            @options[:nick] = user
            @parser.parse!(args)
            q = ".*"
            if args.length > 0
                q = args.join(" ")
            end
            @tasks.query(q, @options[:nick], @options[:start], @options[:end])
        rescue
            "ERROR - Opps you broke it!\n" + usage()
        end
    end
    def usage()
        "\nQuery tasks for a given user via regex:\n" + @parser.to_s
    end
end

bot = Cinch::Bot.new do
    name = "tpsbot"
    tasks = TaskLogger.new("tasks.db")
    commands = {
        :add    => TaskLog.new(tasks),
        :list   => TaskList.new(tasks),
        :query  => TaskQuery.new(tasks),
        :remove => TaskRemove.new(tasks)
    }

    configure do |c|
        c.server = ENV["TPS_IRC_SERVER"]
        c.channels = ["#"+ENV["TPS_CHANNEL"] ]
        c.nick = name
        c.messages_per_second = 1000.0 # weeee
    end

    # in chat messages e.g. NICK: help
    on :message, /^#{name}.*help/ do |m|
        usage = ""
        commands.each do |k, v|
            usage += v.usage()
            usage += "\n"
        end
        m.reply usage
    end

    on :message, /^#{name}.*!log (.+)/ do |m, message|
        args = message.split(" ")
        m.reply commands[:add].run(m.user.nick, args)
    end

    on :message, /^#{name}.*!ls\s?(.+)?/ do |m, message|
        args = []
        if message and message.length > 0
            args = message.split(" ")
        end
        m.reply commands[:list].run(m.user.nick, args)
    end

    on :message, /^#{name}.*!q (.+)/ do |m, message|
        args = message.split(" ")
        m.reply commands[:query].run(m.user.nick, args)
    end

    on :message, /^#{name}.*!rm (\d+)/ do |m, task_id|
        m.reply commands[:remove].run(m.user.nick, [task_id])
    end

    # in chat private messages e.g. /msg NICK help
    on :private, /^help/ do |m|
        usage = ""
        commands.each do |k, v|
            usage += v.usage()
            usage += "\n"
        end
        m.reply usage
    end

    on :private, /^!log (.+)/ do |m, message|
        args = message.split(" ")
        m.reply commands[:add].run(m.user.nick, args)
    end

    on :private, /^!ls\s?(.+)?/ do |m, message|
        args = []
        if message and message.length > 0
            args = message.split(" ")
        end
        m.reply commands[:list].run(m.user.nick, args)
    end

    on :private, /^!q (.+)/ do |m, message|
        args = message.split(" ")
        m.reply commands[:query].run(m.user.nick, args)
    end

    on :private, /^!rm (\d+)/ do |m, task_id|
        m.reply commands[:remove].run(m.user.nick, [task_id])
    end
end

bot.start
