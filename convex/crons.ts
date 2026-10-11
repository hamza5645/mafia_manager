import { cronJobs } from "convex/server";
import { internal } from "./_generated/api";

const crons = cronJobs();

// Cancels abandoned rooms and deletes old room data (see cleanup.ts).
crons.hourly("clean up rooms", { minuteUTC: 17 }, internal.cleanup.sweep);

export default crons;
