class BookingError < StandardError
  attr_reader :message

  def initialize(message)
    @message = message
  end
end

class TimeLog < ActiveRecord::Base
  unloadable

  attr_accessible :user_id, :started_on, :stopped_at, :project_id, :comments, :issue_id, :spent_time, :bookable
  attr_accessor :issue_id, :spent_time
  belongs_to :user
  has_many :time_bookings, :dependent => :delete_all
  has_many :time_entries, :through => :time_bookings

  scope :bookable, where(:bookable => true)

#  belongs_to :project

  def initialize(arguments = nil, *args)
    super(arguments)
  end

  # if issue is the only parameter we get, we will book the whole time to one issue
  # method returns true if all works well, false otherwise
  def add_booking(args = {})
    # TODO not set activity_id default value to 1 / only for testing because redmine requires activity_id
    default_args = {:started_on => self.started_on, :stopped_at => self.stopped_at, :comments => self.comments, :activity_id => 1, :issue => nil, :spent_time => nil, :virtual => false, :project_id => self.project_id}
    args = default_args.merge(args)

    # TODO check time boundaries
    args[:started_on] = Time.parse(tt_log_date + " " + args[:start_time]) if args[:start_time].is_a? String
    args[:stopped_at] = Time.parse(tt_log_date + " " + args[:stop_time]) if args[:stop_time].is_a? String

    # basic calculations are always the same
    args[:spent_time].nil? ? args[:hours] = hours_spent(args[:started_on], args[:stopped_at]) : args[:hours] = help.time_string2hour(args[:spent_time])
    args[:stopped_at] = Time.at(args[:started_on].to_i + (args[:hours] * 3600).to_i).getlocal

    raise BookingError, l(:error_booking_negative_time) if args[:hours] <= 0
    raise BookingError, l(:error_booking_to_much_time) if args[:hours] > bookable_hours

    args[:time_log_id] = self.id
    # userid of booking will be set to the user who created timeLog, even if the admin will create the booking
    args[:user_id] = self.user_id
    tb = TimeBooking.create(args)
    # tb.persisted? will be true if transaction was successfully completed
    if tb.persisted?
      self.bookable = (bookable_hours - tb.hours_spent > 0)
      self.save!
    else
      false
    end
  end

  # returns the hours between two timestamps
  def hours_spent(time1 = started_on, time2 = stopped_at)
    ((time2.to_i - time1.to_i) / 3600.0).to_f
  end

  def get_formatted_bookable_hours
    help.time_dist2string((bookable_hours*3600).to_i)
  end

  def get_formatted_start_time
    self.started_on.to_time.localtime.strftime("%H:%M:%S") unless self.started_on.nil?
  end

  def get_formatted_stop_time
    self.stopped_at.to_time.localtime.strftime("%H:%M:%S") unless self.stopped_at.nil?
  end

  def tt_log_date
    self.started_on.to_date.to_s(:db)
  end

  # returns the sum of bookable time of an time entry
  # if log was not booked at all, so the whole time is bookable
  def bookable_hours
    # every gap between the bookings represents bookable time so we sum up the time to show it as bookable time
    time_booked = 0
    time_bookings.each do |tb|
      time_booked += tb.hours_spent
    end
    hours_spent - time_booked
  end

  def check_bookable
    self.bookable = (bookable_hours > 0)
    self.save!
  end
end
