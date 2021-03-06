class Event < Resting
  attr_accessor :client_silenced, :check_silenced, :client_attributes

  def self.all_with_cache
    Rails.cache.fetch("events", :expires_in => 30.seconds, :race_condition_ttl => 10) do
      all
    end
  end

  def self.refresh_cache
    Rails.cache.write("events", Event.all, :expires_in => 30.seconds, :race_condition_ttl => 10)
  end

  def resolve
    self.delete("#{self.client}/#{self.check}")
  end

  def self.single(query)
    Event.all_with_cache.select{|event| query == "#{event.client}_#{event.check}"}[0]
  end

  def client_silenced
    stashes = Stash.stashes
    if stashes.include?("silence/#{self.client}")
      stashes["silence/#{self.client}"]
    else
      nil
    end
  end

  def check_silenced
    stashes = Stash.stashes
    if stashes.include?("silence/#{self.client}/#{self.check}")
      stashes["silence/#{self.client}/#{self.check}"]
    else
      nil
    end
  end

  def self.manual_resolve(client, check, user)
    event = Event.single("#{client}_#{check}")
    Log.log(user, client, "resolve", nil, event)
    self.delete("events/#{client}/#{check}")
  end

  def self.silence_client(client, description, user, expire_at = nil, log = true, downtime_id = nil)
    Log.log(user, client, "silence", description) if log
    post_data = {:description => description, :owner => user.email, :timestamp => Time.now.to_i }
    post_data[:expire_at] = expire_at unless expire_at.nil?
    post_data[:downtime_id] = downtime_id unless downtime_id.nil?
    Stash.create("silence/#{client}", post_data)
  end

  def self.silence_check(client, check, description, user, expire_at = nil, log = true, downtime_id = nil)
    event = Event.single("#{client}_#{check}")
    Log.log(user, client, "silence", description, event) if log
    post_data = {:description => description, :owner => user.email, :timestamp => Time.now.to_i }
    post_data[:expire_at] = expire_at unless expire_at.nil?
    post_data[:downtime_id] = downtime_id unless downtime_id.nil?
    Stash.create("silence/#{client}/#{check}", post_data)
  end

  def self.unsilence_client(client, user)
    Log.log(user, client, "unsilence")
    Stash.delete("stashes/silence/#{client}")
  end

  def self.unsilence_check(client, check, user)
    event = Event.single("#{client}_#{check}")
    Log.log(user, client, "unsilence", nil, event)
    Stash.delete("stashes/silence/#{client}/#{check}")
  end

  def sort_val
    # Could use a custom sorter here, as Critical is == 2 and Warning == 1
    case self.status
    when 2
      1
    when 1
      2
    else
      3
    end
  end

  def client_attributes
    Rails.cache.fetch(self.client, :expires_in => 5.minutes, :race_condition_ttl => 10) do
      JSON.parse(Client.find(self.client).to_json)
    end
  end

  def client
    client_attributes['name']
  end

  def environment
    client_attributes['environment']
  end
end
