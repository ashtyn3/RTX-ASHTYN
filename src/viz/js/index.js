// import { data } from "./profile.js";

// Set up zoom support
const svg = d3.select("svg");
const inner = svg.select("g");
const zoom = d3.zoom().on("zoom", () => {
  inner.attr("transform", d3.event.transform);
});
svg.call(zoom);

const render = new dagreD3.render();

// Left-to-right layout
const g = new dagreD3.graphlib.Graph();
g.setGraph({
  nodesep: 40,
  ranksep: 20,
  rankdir: "LR",
  marginx: 20,
  marginy: 20,
});

async function draw(isUpdate) {
  const data = JSON.parse(await (await fetch("/kernel")).json());
  for (let i = 0; i < data.nodes.length; i++) {
    // if (worker.count > 10000) {
    //   className += " warn";
    // }
    g.setNode(i, {
      labelType: "html",
      label: `
<div>
<span class="label">${data.nodes[i].instruction.op}</span>
<span class="label">${data.nodes[i].instruction.dtype}</span>
</div>
`,
      rx: 5,
      ry: 5,
      padding: 10,
    });

    // if (worker.inputQueue) {
    // }
  }
  for (const e of data.edges) {
    g.setEdge(e[0], e[1], {
      width: 40,
      arrowhead: "undirected",
      curve: d3.curveBasis,
    });
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
