// app/javascript/controllers/index.js
import { application } from "../application";
import { definitionsFromContext } from "@hotwired/stimulus-webpack-helpers";

const context = require.context(".", true, /\.js$/);
application.load(definitionsFromContext(context));
// This will automatically register all controllers in the current directory