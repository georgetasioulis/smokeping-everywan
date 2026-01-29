/*++ from bonsai.js ++ urlObj  +++++++++++++++++++++++++++++++++++++++++*/
function urlObj(url) {
    var urlBaseAndParameters;

    urlBaseAndParameters = url.split("?");
    this.urlBase = urlBaseAndParameters[0];
    this.urlParameters = urlBaseAndParameters[1].split(/[;&]/);

    this.getUrlBase = urlObjGetUrlBase;
}

/*++ from bonsai.js ++ urlObjGetUrlBase  +++++++++++++++++++++++++++++++*/

function urlObjGetUrlBase() {
    return this.urlBase;
}


// example with minimum dimensions
var myCropper;

var StartEpoch = 0;
var EndEpoch = 0;



function changeRRDImage(coords, dimensions) {

    var SelectLeft = Math.min(coords.x1, coords.x2);

    var SelectRight = Math.max(coords.x1, coords.x2);

    if (SelectLeft == SelectRight)
        return; // abort if nothing is selected.

    var RRDLeft = 67;        // difference between left border of RRD image and content
    var RRDRight = 26;        // difference between right border of RRD image and content
    var RRDImgWidth = $('zoom').getDimensions().width;       // Width of the Smokeping RRD Graphik
    var RRDImgUsable = RRDImgWidth - RRDRight - RRDLeft;
    var form = $('range_form');

    if (StartEpoch == 0)
        StartEpoch = +$F('epoch_start');

    if (EndEpoch == 0)
        EndEpoch = +$F('epoch_end');

    var DivEpoch = EndEpoch - StartEpoch;

    var Target = $F('target');
    var Hierarchy = $F('hierarchy');

    // construct Image URL
    var myURLObj = new urlObj(document.URL);

    var myURL = myURLObj.getUrlBase();

    // Generate Selected Range in Unix Timestamps
    var LeftFactor = 1;
    var RightFactor = 1;

    if (SelectLeft < RRDLeft)
        LeftFactor = 10;

    StartEpoch = Math.floor(StartEpoch + (SelectLeft - RRDLeft) * DivEpoch / RRDImgUsable * LeftFactor);

    if (SelectRight > RRDImgWidth - RRDRight)
        RightFactor = 10;

    EndEpoch = Math.ceil(EndEpoch + (SelectRight - (RRDImgWidth - RRDRight)) * DivEpoch / RRDImgUsable * RightFactor);


    $('zoom').src = myURL + '?displaymode=a;start=' + StartEpoch + ';end=' + EndEpoch + ';target=' + Target + ';hierarchy=' + Hierarchy;

    myCropper.setParams();

};

// Initialize cropper function
function initSmokepingZoom() {
    // Check if zoom element exists
    var zoomEl = document.getElementById('zoom');
    if (zoomEl != null && typeof Cropper !== 'undefined' && typeof Cropper.Img !== 'undefined') {
        try {
            myCropper = new Cropper.Img(
                'zoom',
                {
                    minHeight: zoomEl.offsetHeight,
                    maxHeight: zoomEl.offsetHeight,
                    onEndCrop: changeRRDImage
                }
            );
            console.log('SmokePing zoom initialized successfully');
        } catch (e) {
            console.error('SmokePing zoom init failed:', e);
        }
    }

    // Menu button handler (optional, may not exist)
    var menuButton = document.getElementById('menu-button');
    if (menuButton && typeof Event !== 'undefined' && typeof Event.observe === 'function') {
        Event.observe(menuButton, 'click', function (e) {
            var sidebar = document.getElementById('sidebar');
            var body = document.body;
            if (sidebar && sidebar.style.left === '0px') {
                body.className = body.className.replace('sidebar-visible', 'sidebar-hidden');
            } else {
                body.className = body.className.replace('sidebar-hidden', 'sidebar-visible');
            }
            if (e.preventDefault) e.preventDefault();
            return false;
        });
    }
}

// Robust initialization - try multiple methods
(function () {
    // Method 1: If DOM already loaded
    if (document.readyState === 'complete' || document.readyState === 'interactive') {
        setTimeout(initSmokepingZoom, 100);
        return;
    }

    // Method 2: DOMContentLoaded
    if (document.addEventListener) {
        document.addEventListener('DOMContentLoaded', function () {
            setTimeout(initSmokepingZoom, 100);
        });
    }

    // Method 3: window.onload fallback
    var oldOnload = window.onload;
    window.onload = function () {
        if (typeof oldOnload === 'function') {
            oldOnload();
        }
        setTimeout(initSmokepingZoom, 100);
    };
})();
