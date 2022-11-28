module EnvHelper
  def self.with_env(temp_env, &block)
    original_env = ENV.to_hash
    temp_env.each { |k, v| ENV[k] = v } # ENV.merge! introduced in ruby 2.7.0. We can use that once we drop support for ruby 2.6
    block.call
    ENV.clear
    ENV.replace(original_env)
  end

  def self.with_reset(&block)
    with_env({}, &block)
  end
end
