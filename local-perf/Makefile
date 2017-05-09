# CoreDNS needs to be running on localhost PORT (1053).
# Need to repeat 'make mig' for a couple of times.
LIMIT:=35000
TIME:=30
PORT:=1053
SERVER:=127.0.0.1

.PHONY: mig
mig:
	./bin/mig-linux_amd64 -s $(SERVER) -p $(PORT) -d domain.lst.mig -l $(LIMIT) -n 100000 -o test.json

.PHONY: queryperf
queryperf:
	./bin/queryperf-linux_amd64 -d domain.lst.queryperf -l $(TIME) -s $(SERVER) -p $(PORT)

.PHONY: clean
clean:
	rm test.json
