// WorkflowEngineTests.swift — NovaControl
// Unit tests for workflow models and template rendering.
// Written by Jordan Koch.

import XCTest
@testable import NovaControl

final class WorkflowEngineTests: XCTestCase {

    // MARK: - WorkflowDefinition

    func testWorkflowDefinitionCodableRoundTrip() throws {
        let def = WorkflowDefinition(
            id: "test-wf",
            name: "Test Workflow",
            trigger: .manual,
            steps: [
                WorkflowDefinition.WorkflowStep(
                    id: "step1", name: "Post to Slack",
                    type_: .postToSlack,
                    config: ["channel": "C12345", "messageTemplate": "Hello {{name}}"],
                    continueOnFailure: false
                )
            ],
            enabled: true
        )

        let data = try JSONEncoder().encode(def)
        let decoded = try JSONDecoder().decode(WorkflowDefinition.self, from: data)

        XCTAssertEqual(decoded.id, "test-wf")
        XCTAssertEqual(decoded.name, "Test Workflow")
        XCTAssertEqual(decoded.steps.count, 1)
        XCTAssertEqual(decoded.steps.first?.type_, .postToSlack)
        XCTAssertTrue(decoded.enabled)
    }

    func testWorkflowTriggerManualCodable() throws {
        let trigger = WorkflowDefinition.WorkflowTrigger.manual
        let data = try JSONEncoder().encode(trigger)
        let decoded = try JSONDecoder().decode(WorkflowDefinition.WorkflowTrigger.self, from: data)
        if case .manual = decoded {
            // pass
        } else {
            XCTFail("Expected .manual trigger, got \(decoded)")
        }
    }

    func testWorkflowTriggerNewActionItemCodable() throws {
        let trigger = WorkflowDefinition.WorkflowTrigger.newActionItem(priority: "high")
        let data = try JSONEncoder().encode(trigger)
        let decoded = try JSONDecoder().decode(WorkflowDefinition.WorkflowTrigger.self, from: data)
        if case .newActionItem(let priority) = decoded {
            XCTAssertEqual(priority, "high")
        } else {
            XCTFail("Expected .newActionItem trigger, got \(decoded)")
        }
    }

    func testWorkflowTriggerActionItemCompletedCodable() throws {
        let trigger = WorkflowDefinition.WorkflowTrigger.actionItemCompleted
        let data = try JSONEncoder().encode(trigger)
        let decoded = try JSONDecoder().decode(WorkflowDefinition.WorkflowTrigger.self, from: data)
        if case .actionItemCompleted = decoded {
            // pass
        } else {
            XCTFail("Expected .actionItemCompleted trigger, got \(decoded)")
        }
    }

    // MARK: - WorkflowRun

    func testWorkflowRunStatusCodable() throws {
        let statuses: [WorkflowRun.RunStatus] = [.running, .completed, .failed, .retrying]
        for status in statuses {
            let data = try JSONEncoder().encode(status)
            let decoded = try JSONDecoder().decode(WorkflowRun.RunStatus.self, from: data)
            XCTAssertEqual(decoded, status)
        }
    }

    func testWorkflowRunInit() {
        let run = WorkflowRun(id: UUID(), workflowId: "test-wf",
                              triggeredAt: Date(), triggerContext: "manual",
                              status: .running, stepResults: [])
        XCTAssertEqual(run.workflowId, "test-wf")
        XCTAssertEqual(run.status, .running)
        XCTAssertTrue(run.stepResults.isEmpty)
        XCTAssertNil(run.completedAt)
        XCTAssertNil(run.error)
    }

    func testWorkflowStepResultInit() {
        let result = WorkflowRun.StepResult(stepId: "notify",
                                             status: "ok",
                                             output: "Posted to #nova-chat",
                                             durationMs: 142)
        XCTAssertEqual(result.stepId, "notify")
        XCTAssertEqual(result.status, "ok")
        XCTAssertEqual(result.durationMs, 142)
    }

    // MARK: - StepType

    func testStepTypeCodable() throws {
        let types: [WorkflowDefinition.WorkflowStep.StepType] = [
            .postToSlack, .createJiraTicket, .sendEmail, .webhook, .wait
        ]
        for type in types {
            let data = try JSONEncoder().encode(type)
            let decoded = try JSONDecoder().decode(
                WorkflowDefinition.WorkflowStep.StepType.self, from: data)
            XCTAssertEqual(decoded, type)
        }
    }

    func testStepTypeRawValues() {
        XCTAssertEqual(WorkflowDefinition.WorkflowStep.StepType.postToSlack.rawValue, "postToSlack")
        XCTAssertEqual(WorkflowDefinition.WorkflowStep.StepType.createJiraTicket.rawValue, "createJiraTicket")
        XCTAssertEqual(WorkflowDefinition.WorkflowStep.StepType.sendEmail.rawValue, "sendEmail")
        XCTAssertEqual(WorkflowDefinition.WorkflowStep.StepType.webhook.rawValue, "webhook")
        XCTAssertEqual(WorkflowDefinition.WorkflowStep.StepType.wait.rawValue, "wait")
    }

    // MARK: - Multi-Step Workflow Codable

    func testMultiStepWorkflowCodable() throws {
        let def = WorkflowDefinition(
            id: "multi",
            name: "Multi-Step",
            trigger: .actionItemCompleted,
            steps: [
                WorkflowDefinition.WorkflowStep(
                    id: "jira", name: "Create Jira", type_: .createJiraTicket,
                    config: ["projectKey": "NOVA"], continueOnFailure: true),
                WorkflowDefinition.WorkflowStep(
                    id: "wait", name: "Pause", type_: .wait,
                    config: ["seconds": "2"], continueOnFailure: true),
                WorkflowDefinition.WorkflowStep(
                    id: "notify", name: "Slack", type_: .postToSlack,
                    config: ["channel": "C0AMNQ5GX70"], continueOnFailure: false),
            ],
            enabled: false
        )

        let data = try JSONEncoder().encode(def)
        let decoded = try JSONDecoder().decode(WorkflowDefinition.self, from: data)

        XCTAssertEqual(decoded.steps.count, 3)
        XCTAssertEqual(decoded.steps[0].type_, .createJiraTicket)
        XCTAssertEqual(decoded.steps[1].type_, .wait)
        XCTAssertEqual(decoded.steps[2].type_, .postToSlack)
        XCTAssertTrue(decoded.steps[0].continueOnFailure)
        XCTAssertFalse(decoded.steps[2].continueOnFailure)
        XCTAssertFalse(decoded.enabled)
    }
}
