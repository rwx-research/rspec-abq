module EnvHelper
  def self.with_env(temp_env, &block)
    original_env = ENV.to_hash
    ENV.merge!(temp_env)
    block.call
    ENV.clear
    ENV.merge!(original_env)
  end

  def self.with_reset(&block)
    with_env({}, &block)
  end
end
