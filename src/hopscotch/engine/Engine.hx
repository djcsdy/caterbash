package hopscotch.engine;

import hopscotch.debug.PerformanceInfo;
import hopscotch.Static;
import hopscotch.Playfield;
import hopscotch.debug.Console;
import hopscotch.debug.IConsole;
import flash.events.Event;
import flash.display.Bitmap;
import flash.display.BitmapData;
import hopscotch.errors.ArgumentError;
import hopscotch.errors.ArgumentNullError;
import hopscotch.input.IInput;
import hopscotch.engine.ScreenSize;
import flash.display.DisplayObjectContainer;

class Engine {
    public var playfield:Playfield;
    public var inputs(default, null):Array<IInput>;

    public var performanceInfo(default, null):PerformanceInfo;
    public var console:IConsole;

    var renderTarget:DisplayObjectContainer;
    var screenSize:ScreenSize;

    var targetBitmapData:BitmapData;
    var targetBitmap:Bitmap;

    var framesPerSecond:Float;
    var framesPerMillisecond:Float;

    var timeSource:ITimeSource;

    var running:Bool;
    var startTime:Int;

    var previousFrame:Int;

    var previousPlayfield:Playfield;

    var previousConsole:IConsole;

    var lastFrameFinishedTime:Int;

    var performanceSamplesCount:Int;

    var updateFramesPerSecondAverage:RollingAverage;
    var renderFramesPerSecondAverage:RollingAverage;

    var updateTimeMsAverage:RollingAverage;
    var graphicUpdateTimeMsAverage:RollingAverage;
    var renderTimeMsAverage:RollingAverage;
    var systemTimeMsAverage:RollingAverage;

    public function new (renderTarget:DisplayObjectContainer,
            width:Int, height:Int, framesPerSecond:Float,
            timeSource:ITimeSource=null) {
        if (renderTarget == null) {
            throw new ArgumentNullError("renderTarget");
        }

        if (width <= 0) {
            throw new ArgumentError("width out of range");
        }

        if (height <= 0) {
            throw new ArgumentError("height out of range");
        }

        if (framesPerSecond <= 0) {
            throw new ArgumentError("framesPerSecond out of range");
        }

        this.renderTarget = renderTarget;
        this.screenSize = new ScreenSize(width, height);

        targetBitmapData = new BitmapData(width, height, false, 0x000000);
        targetBitmap = new Bitmap(targetBitmapData);

        this.framesPerSecond = framesPerSecond;
        framesPerMillisecond = framesPerSecond / 1000;

        this.timeSource =
                if (timeSource == null) new TimeSource()
                else timeSource;

        playfield = null;

        inputs = [];

        running = false;
        startTime = 0;

        previousFrame = 0;

        previousPlayfield = null;

        performanceInfo = new PerformanceInfo();
        performanceInfo.targetFramesPerSecond = framesPerSecond;
        performanceInfo.updateFramesPerSecond = framesPerSecond;
        performanceInfo.renderFramesPerSecond = framesPerSecond;

        console = new Console();
        previousConsole = null;

        lastFrameFinishedTime = -1;

        performanceSamplesCount = Math.floor(framesPerSecond);

        updateFramesPerSecondAverage = new RollingAverage(performanceSamplesCount);
        updateFramesPerSecondAverage.push(framesPerSecond);

        renderFramesPerSecondAverage = new RollingAverage(performanceSamplesCount);
        renderFramesPerSecondAverage.push(framesPerSecond);

        updateTimeMsAverage = new RollingAverage(performanceSamplesCount);
        graphicUpdateTimeMsAverage = new RollingAverage(performanceSamplesCount);
        renderTimeMsAverage = new RollingAverage(performanceSamplesCount);
        systemTimeMsAverage = new RollingAverage(performanceSamplesCount);
    }

    public function start():Void {
        if (!running) {
            running = true;
            startTime = Math.floor(timeSource.getTime() -
                    (previousFrame - 1) / framesPerMillisecond);

            renderTarget.addChild(targetBitmap);

            renderTarget.addEventListener(Event.ENTER_FRAME, onEnterFrame);
        }
    }

    public function stop():Void {
        if (running) {
            running = false;

            renderTarget.removeChild(targetBitmap);

            renderTarget.removeEventListener(Event.ENTER_FRAME, onEnterFrame);

            lastFrameFinishedTime = -1;
        }
    }

    function onEnterFrame(event:Event):Void {
        if (!running) {
            return;
        }

        var now = timeSource.getTime();
        var targetFrame:Int = Math.floor(1 + (now - startTime) * framesPerMillisecond);

        if (lastFrameFinishedTime >= 0) {
            systemTimeMsAverage.push(now - lastFrameFinishedTime);
        }

        if (targetFrame > previousFrame) {
            var framesAdvanced = targetFrame - previousFrame;
            var updateFramesAdvanced:Int;

            if (framesAdvanced > 5) {
                updateFramesAdvanced = 5;
                startTime += Math.ceil((targetFrame - previousFrame - 5) * framesPerMillisecond);
                targetFrame = previousFrame + 5;
            } else {
                updateFramesAdvanced = framesAdvanced;
            }

            var time1:Int, time2:Int, time3:Int;

            var frame = previousFrame + 1;
            while (frame <= targetFrame) {
                time1 = timeSource.getTime();
                update(frame);
                time2 = timeSource.getTime();
                updateGraphic(frame);
                time3 = timeSource.getTime();

                updateTimeMsAverage.push(time2 - time1);
                graphicUpdateTimeMsAverage.push(time3 - time2);

                ++frame;
            }
            previousFrame = frame;

            time1 = timeSource.getTime();
            render();
            time2 = timeSource.getTime();

            renderTimeMsAverage.push(time2 - time1);

            performanceInfo.systemTimeMs = systemTimeMsAverage.average();
            performanceInfo.updateTimeMs = updateTimeMsAverage.average();
            performanceInfo.graphicUpdateTimeMs = graphicUpdateTimeMsAverage.average();
            performanceInfo.renderTimeMs = renderTimeMsAverage.average();

            var updateFramesPerSecond = framesPerSecond / (framesAdvanced - updateFramesAdvanced + 1);
            var renderFramesPerSecond = framesPerSecond / framesAdvanced;

            var i:Int = 0;
            while (i < framesAdvanced && i < framesPerSecond) {
                updateFramesPerSecondAverage.push(updateFramesPerSecond);
                renderFramesPerSecondAverage.push(renderFramesPerSecond);
            }

            performanceInfo.updateFramesPerSecond = updateFramesPerSecondAverage.average();
            performanceInfo.renderFramesPerSecond = renderFramesPerSecondAverage.average();
        }

        lastFrameFinishedTime = timeSource.getTime();
    }

    function update(frame:Int):Void {
        if (playfield != previousPlayfield) {
            if (previousPlayfield != null) {
                previousPlayfield.end();
            }

            if (playfield != null) {
                playfield.begin(frame - 1);
            }

            previousPlayfield = playfield;
        }

        if (console != previousConsole) {
            if (previousConsole != null) {
                previousConsole.end();
            }

            if (console != null) {
                console.begin(frame);
            }

            previousConsole = console;
        }

        for (input in inputs) {
            if (input != null) {
                input.update(frame);
            }
        }

        if (playfield != null && playfield.active) {
            playfield.update(frame);
        }

        if (console != null && console.enabled) {
            console.update(frame, performanceInfo);
        }
    }

    function updateGraphic(frame:Int):Void {
        if (playfield != null && playfield.active) {
            playfield.updateGraphic(frame, screenSize);
        }
    }

    function render():Void {
        targetBitmapData.fillRect(targetBitmapData.rect, 0x000000);

        if (console == null || !console.enabled) {
            if (playfield != null && playfield.visible) {
                playfield.render(targetBitmapData, Static.origin, Static.identity);
            }
        } else {
            console.render(targetBitmapData, playfield);
        }
    }
}