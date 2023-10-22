import AppwriteService from "./appwrite.js";
import { throwIfMissing } from "./utils.js";

export default async (context) => {
    throwIfMissing(process.env, [
        "APPWRITE_API_KEY",
        "RETENTION_PERIOD_DAYS",
        "APPWRITE_BUCKET_ID",
    ]);

    const appwrite = new AppwriteService();

    try {
        await appwrite.cleanPartcipantsCollection();
    } catch (e) {
        context.error(String(e));
    }

    try {
        await appwrite.cleanActivePairsCollection();
    } catch (e) {
        context.error(String(e));
    }

    return context.res.send("Database Cleanup completed");
};
