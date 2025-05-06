var workers = {
  identifier: {
    consumers: 2,
    count: 20,
  },
  "lost-and-found": {
    consumers: 1,
    count: 1,
    inputQueue: "identifier",
    inputThroughput: 50,
  },
  monitor: {
    consumers: 1,
    count: 0,
    inputQueue: "identifier",
    inputThroughput: 50,
  },
  "meta-enricher": {
    consumers: 4,
    count: 9900,
    inputQueue: "identifier",
    inputThroughput: 50,
  },
  "geo-enricher": {
    consumers: 2,
    count: 1,
    inputQueue: "meta-enricher",
    inputThroughput: 50,
  },
  "elasticsearch-writer": {
    consumers: 0,
    count: 9900,
    inputQueue: "geo-enricher",
    inputThroughput: 50,
  },
};

// Set up zoom support
var svg = d3.select("svg"),
  inner = svg.select("g"),
  zoom = d3.zoom().on("zoom", function () {
    inner.attr("transform", d3.event.transform);
  });
svg.call(zoom);

var render = new dagreD3.render();

// Left-to-right layout
var g = new dagreD3.graphlib.Graph();
g.setGraph({
  nodesep: 40,
  ranksep: 20,
  rankdir: "LR",
  marginx: 20,
  marginy: 20,
});

function draw(isUpdate) {
  for (var id in workers) {
    var worker = workers[id];
    var className = worker.consumers ? "running" : "stopped";
    // if (worker.count > 10000) {
    //   className += " warn";
    // }
    g.setNode(id, {
      labelType: "html",
      label: `<span class="label">text</span>`,
      rx: 5,
      ry: 5,
      padding: 10,
      class: className,
    });

    if (worker.inputQueue) {
      g.setEdge(worker.inputQueue, id, {
        width: 40,
        arrowhead: "undirected",
        curve: d3.curveBasis,
      });
    }
  }

  inner.call(render, g);

  // Zoom and scale to fit
  var graphWidth = g.graph().width + 80;
  var graphHeight = g.graph().height + 40;
  var width = parseInt(svg.style("width").replace(/px/, ""));
  var height = parseInt(svg.style("height").replace(/px/, ""));
  var zoomScale = Math.min(width / graphWidth, height / graphHeight);
  var translateX = width / 2 - (graphWidth * zoomScale) / 2;
  var translateY = height / 2 - (graphHeight * zoomScale) / 2;
  var svgZoom = isUpdate ? svg.transition().duration(500) : svg;
  svgZoom.call(
    zoom.transform,
    d3.zoomIdentity.translate(translateX, translateY).scale(zoomScale),
  );
}

// Initial draw, once the DOM is ready
document.addEventListener("DOMContentLoaded", draw);
