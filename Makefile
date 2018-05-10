

#---------------------------------------------
# Copy files to the web directory for 
# testing in a browser
#---------------------------------------------
web:
	cp ./vm/dist/web/scratch-vm.min.js ./web/lib/scratch-vm.min.js
	cp ./vm/dist/web/scratch-vm.min.js.map ./web/lib/scratch-vm.min.js.map
	cp ./blocks/blockly_compressed_vertical.js ./web/lib/blockly_vertical.js
	cp ./blocks/msg/messages.js ./web/lib/messages.js
	cp ./blocks/blocks_compressed.js ./web/lib/blocks.js
	cp ./blocks/blocks_compressed_vertical.js ./web/lib/blocks_vertical.js
	cp -r ./blocks/media ./web

.PHONY: web
