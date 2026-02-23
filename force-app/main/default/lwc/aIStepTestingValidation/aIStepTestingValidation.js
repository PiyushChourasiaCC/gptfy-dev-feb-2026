import { LightningElement, api } from 'lwc';

export default class AIStepTestingValidation extends LightningElement {
    @api wizardState;
    @api agentConfig;

    handleComplete() {
        this.dispatchEvent(new CustomEvent('stepcomplete', {
            detail: {
                stepData: { testResults: { functionsExecuted: 5, passRate: 0.9, averageResponseTime: 1200 } },
                isValid: true,
                stepNumber: 5
            }
        }));
    }
}