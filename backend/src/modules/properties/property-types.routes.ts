// modules/properties/property-types.routes.ts
import { Router } from 'express';
import { PropertiesController } from './properties.controller';
import { authGuard } from '@shared/middleware/auth-guard';

const controller = new PropertiesController();
export const propertyTypesRouter = Router();

propertyTypesRouter.use(authGuard);
propertyTypesRouter.get('/', controller.listTypes);
propertyTypesRouter.get('/:typeKey/template', controller.previewTemplate);
