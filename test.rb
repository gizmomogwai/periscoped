file = ARGV[0]
io = File.new(file, "r")
while true
    putc io.readchar
    STDOUT.flush
    sleep(0.0001)
end
