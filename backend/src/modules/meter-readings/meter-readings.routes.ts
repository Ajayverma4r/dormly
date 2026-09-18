// modules/meter-readings/meter-readings.routes.ts
import { Router } from 'express';
import {
  MeterReadingsController,
  uploadMeterImageMiddleware,
} from './meter-readings.controller';

const controller = new MeterReadingsController();
export const meterReadingsRouter = Router({ mergeParams: true });

meterReadingsRouter.get('/', controller.list);
meterReadingsRouter.post('/', uploadMeterImageMiddleware, controller.submit);
