import "@hotwired/turbo-rails";
import { Application } from "@hotwired/stimulus";
import * as bootstrap from "bootstrap";
import L from "leaflet";
// import "leaflet/dist/leaflet.css";

window.bootstrap = bootstrap;
window.L = L;

const application = Application.start();
window.Stimulus = application;

// ✅ Register all controllers manually
import AddressController from "./controllers/address_controller";
import AdminGuidelinesController from "./controllers/admin_guidelines_controller";
import ConfirmationController from "./controllers/confirmation_controller";
import DocumentUploadController from "./controllers/document_upload_controller";
import FlashController from "./controllers/flash_controller";
import HelloController from "./controllers/hello_controller";
import IdSwitcherController from "./controllers/id_switcher_controller";
import MapController from "./controllers/map_controller";
import ModalConfirmationController from "./controllers/modal_confirmation_controller";
import ModerationController from "./controllers/moderation_controller";
import PostalCodeController from "./controllers/postal_code_controller";
import ReasonController from "./controllers/reason_controller";
import SectorController from "./controllers/sector_controller";
import SelectAllController from "./controllers/select_all_controller";
import SubmissionFilterController from "./controllers/submission_filter_controller";
import TooltipController from "./controllers/tooltip_controller";
import UnitController from "./controllers/unit_controller";
import BonidLookupController from "./controllers/bonid_lookup_controller";
import QrScannerController from "./controllers/qr_scanner_controller";

// Register each controller by name
application.register("address", AddressController);
application.register("admin-guidelines", AdminGuidelinesController);
application.register("confirmation", ConfirmationController);
application.register("document-upload", DocumentUploadController);
application.register("flash", FlashController);
application.register("hello", HelloController);
application.register("id-switcher", IdSwitcherController);
application.register("map", MapController);
application.register("modal-confirmation", ModalConfirmationController);
application.register("moderation", ModerationController);
application.register("postal-code", PostalCodeController);
application.register("reason", ReasonController);
application.register("sector", SectorController);
application.register("select-all", SelectAllController);
application.register("submission-filter", SubmissionFilterController);
application.register("tooltip", TooltipController);
application.register("unit", UnitController);
application.register("bonid-lookup", BonidLookupController);
application.register("qr-scanner", QrScannerController);
