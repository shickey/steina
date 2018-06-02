(function () {

    /**
     * Window "onload" handler.
     * @return {void}
     */
    function onLoad () {

        Blockly.VerticalFlyout.prototype.DEFAULT_WIDTH = 300;

        // Instantiate the VM and create an empty project
        var vm = new window.VirtualMachine();
        window.vm = vm;

        var defaultProject = {
          "targets": [
            {
              "isStage": true,
              "name": "Stage",
              "variables": {},
              "lists": {},
              "broadcasts": {},
              "blocks": {},
              "currentCostume": 0,
              "costumes": [
                {
                  "assetId": "739b5e2a2435f6e1ec2993791b423146",
                  "name": "backdrop1",
                  "bitmapResolution": 1,
                  "md5ext": "739b5e2a2435f6e1ec2993791b423146.png",
                  "dataFormat": "png",
                  "rotationCenterX": 240,
                  "rotationCenterY": 180
                }
              ],
              "sounds": [],
              "volume": 100,
            }
          ],
          "meta": {
            "semver": "3.0.0",
            "vm": "0.1.0",
            "agent": "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_13_3) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/65.0.3325.181 Safari/537.36"
          }
        }
        vm.loadProject(defaultProject).then(() => {
            // Instantiate scratch-blocks and attach it to the DOM.
            var workspace = Blockly.inject('blocks', {
                media: './media/',
                scrollbars: false,
                trashcan: false,
                horizontalLayout: false,
                sounds: false,
                zoom: {
                    controls: false,
                    wheel: false,
                    startScale: 1.0
                },
                colours: {
                    workspace: '#334771',
                    flyout: '#283856',
                    scrollbar: '#24324D',
                    scrollbarHover: '#0C111A',
                    insertionMarker: '#FFFFFF',
                    insertionMarkerOpacity: 0.3,
                    fieldShadow: 'rgba(255, 255, 255, 0.3)',
                    dragShadowOpacity: 0.6
                }
            });
            window.workspace = workspace;

            // Get XML toolbox definition
            var toolbox = document.getElementById('toolbox');
            window.toolbox = toolbox;

            vm.addListener('EXTENSION_ADDED', (blocksInfo) => {
                // Generate the proper blocks and refresh the toolbox
                Blockly.defineBlocksWithJsonArray(blocksInfo.map(blockInfo => blockInfo.json));
                workspace.updateToolbox(toolbox);
            });

            vm.extensionManager.loadExtensionURL('video');

            // // Disable long-press
            Blockly.longStart_ = function() {};

            // Attach blocks to the VM
            workspace.addChangeListener(vm.blockListener);
            var flyoutWorkspace = workspace.getFlyout().getWorkspace();
            flyoutWorkspace.addChangeListener(vm.flyoutBlockListener);

            // Handle VM events
            vm.on('SCRIPT_GLOW_ON', function(data) {
                workspace.glowStack(data.id, true);
            });
            vm.on('SCRIPT_GLOW_OFF', function(data) {
                workspace.glowStack(data.id, false);
            });
            vm.on('BLOCK_GLOW_ON', function(data) {
                workspace.glowBlock(data.id, true);
            });
            vm.on('BLOCK_GLOW_OFF', function(data) {
                workspace.glowBlock(data.id, false);
            });
            vm.on('VISUAL_REPORT', function(data) {
                workspace.reportValue(data.id, data.value);
            });

            vm.on('workspaceUpdate', (data) => {
                workspace.removeChangeListener(vm.blockListener);
                const dom = Blockly.Xml.textToDom(data.xml);
                Blockly.Xml.clearWorkspaceAndLoadFromXml(dom, workspace);
                workspace.addChangeListener(vm.blockListener);
            })

            // Extension event handlers
            bindExtensionHandler();

            vm.runtime.currentStepTime = 1000.0 / 30.0;
            /*******************************************************************
             *******************************************************************
             *
             * NOTE:
             *
             * We purposefully do NOT start the vm here (or in fact, at all).
             * Instead, we leave it up to iOS to manually drive the VM run loop
             * so that we can lock it to the vertical blink on the display.
             *
             *******************************************************************
             *******************************************************************/

            // Create external interface so iOS can call into JS
            function tick() {
                vm.runtime._step();
            }

            function createVideoTarget(id, fps, frames, blocksJson) {
                vm.createVideoTarget(id, {
                    fps,
                    frames,
                    blocksJson
                })
            }

            function getVideoTargets() {
                return vm.getVideoTargets().map(t => t.toJSON());
            }

            function beginDraggingVideo(id) {
              vm.startDrag(id);
            }

            function updateDraggingVideo(id, x, y) {
              vm.updateDrag({
                x: x,
                y: y
              });
            }

            function endDraggingVideo(id) {
              vm.stopDrag(id);
            }

            window.Steina = {
                tick,
                createVideoTarget,
                getVideoTargets,
                beginDraggingVideo,
                updateDraggingVideo,
                endDraggingVideo
            }

            if (window.steinaMsg) {
                window.steinaMsg.postMessage({
                    message: 'READY'
                });
            }

        });

        

    }

    // /**
    //  * Binds the extension interface to `window.ext`.
    //  * @return {void}
    //  */
    function bindExtensionHandler () {
        if (typeof webkit === 'undefined') return;
        if (typeof webkit.messageHandlers === 'undefined') return;
        if (typeof webkit.messageHandlers.steinaMsg === 'undefined') return;
        window.steinaMsg = webkit.messageHandlers.steinaMsg;

        // // Swizzle console methods so we can also get them through the iOS console
        // if (typeof webkit.messageHandlers.cons === 'undefined') return;
        // window.cons = webkit.messageHandlers.cons;
        // var oldConsoleLog = window.console.log;
        // var oldConsoleError = window.console.error;
        // var oldConsoleWarn = window.console.warn;
        // var oldConsoleInfo = window.console.info;
        // window.console.log = (message) => {
        //   oldConsoleLog(message);
        //   window.cons.postMessage({
        //     level: 'LOG'
        //     message: message
        //   })
        // }
        // window.console.error = (message) => {
        //   oldConsoleError(message);
        //   window.cons.postMessage({
        //     level: 'ERROR'
        //     message: message
        //   })
        // }
        // window.console.warn = (message) => {
        //   oldConsoleWarn(message);
        //   window.cons.postMessage({
        //     level: 'WARN'
        //     message: message
        //   })
        // }
        // window.console.info = (message) => {
        //   oldConsoleInfo(message);
        //   window.cons.postMessage({
        //     level: 'INFO'
        //     message: message
        //   })
        // }

        if (typeof webkit.messageHandlers.cons === 'undefined') return;
        window.cons = webkit.messageHandlers.cons;
        window.console.log = window.console.error = window.console.warn = window.console.info = (message) => {
            window.cons.postMessage({
                message: message
            });
        };
    }


    /**
     * Bind event handlers.
     */
    window.onload = onLoad;

})();
