// modules/staff/invitations.routes.ts
//
// Deliberately uses ONLY authGuard, not requireContext — a person must be
// able to see and accept invitations even before they've selected a context
// (which, for a brand-new manager/staff, doesn't exist yet until they accept).

import { Router } from 'express';
import { InvitationsController } from './invitations.controller';
import { authGuard } from '@shared/middleware/auth-guard';

const controller = new InvitationsController();
export const invitationsRouter = Router();

invitationsRouter.use(authGuard);
invitationsRouter.get('/', controller.list);
invitationsRouter.post('/:assignmentId/accept', controller.accept);
invitationsRouter.post('/:assignmentId/decline', controller.decline);