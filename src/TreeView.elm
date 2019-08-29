module TreeView exposing
  ( CssClasses, defaultCssClasses
  , NodeUid(..), uidOf, Configuration
  , Model, initializeModel, Msg
  , update, view, subscriptions
  , expandAll, collapseAll, updateNodeData, getSelected, getVisibleAnnotatedNodes
  , updateExpandedStateOf
  , Configuration2, initializeModel2, Msg2 (..), update2, view2, subscriptions2
  )

{-| Tree view facility.

* Construct a tree of [Node](Tree#Node) instances, embedding your data into them.
* Initialize a model.
* Interact with it (conventional TEA)
  * Arrow-key interactions require the call-site to use the subscriptions of the
    facility, otherwise only mouse-click driven interactions work, see
    [`subscriptions`](#subscriptions).
* Provide manually the required CSS definitions to make your tree view look usable & nice,
  * for a basic working CSS see
  [Demo CSS](https://github.com/dosarf/elm-tree-view/tree/master/demo/src/assets/tree-view.css).

Also, non-leaf nodes can also be collapsed / expanded programmatically, as well
as selected node and visible nodes can be retrieved.

## Node uid

@docs NodeUid, uidOf

## Configuration

@docs Configuration, defaultCssClasses, CssClasses

## Good old [TEA](https://guide.elm-lang.org/architecture/) types and functions
@docs Model, initializeModel, Msg, update, view, subscriptions

## Working with tree views

@docs getSelected, getVisibleAnnotatedNodes, expandAll, collapseAll, updateExpandedStateOf, updateNodeData

## Custom rendering nodes

@docs Configuration2, initializeModel2, Msg2, update2, view2, subscriptions2
-}

import List.Extra as LX
import Browser.Events as Events
import Html exposing (Attribute, Html, div, label, table, tr, td, text)
import Html.Attributes exposing (class, classList, colspan)
import Html.Events exposing (onClick)
import Json.Decode as JsonDec
import Set
import Tree as T

{-| Tree view tracks internal state (collapsed/expanded, etc) of the nodes
and identifies them by their node uid, thus a node uids must be comparable.
* Node uids are to be unique in the scope of the forest being displayed by
a tree view.
* Call-site will define how to calculate the node uid for a given node, see
  `uidThunk` in [`Configuration`](#Configuration).

To make clear when a function signature is referring to a node uid and not
just any other old comparable value, this product type is used.
-}
type NodeUid comparable =
    NodeUid comparable

{-| Obtains the actual node uid (comparable) value out of the product type
value.
-}
uidOf : NodeUid comparable -> comparable
uidOf nUid =
    case nUid of
        NodeUid nodeUid ->
            nodeUid

{-| Defines CSS classes to be used for a tree view. Different tree views can
be made to look different by initializing them with a different
set of CSS class names, see also [`defaultCssClasses`](#defaultCssClasses).

The actual CSS definitions must _always_ be provided manually, even when the
default CSS class names are used. For a working default CSS declarations,
see [Demo CSS](https://github.com/dosarf/elm-tree-view/tree/master/demo/src/assets/tree-view.css).
-}
type alias CssClasses =
    { treeViewCssClass : String
    , selectedTreeNodeCssClass : String
    , indentationCssClass : String
    , bulletExpandedCssClass : String
    , bulletCollapsedCssClass : String
    , bulletLeafCssClass : String
    }

{-| Some CSS class names you can use by default.

A tree view is constructed out of HTML elements `table`, `tr` and `td`, and one
or more of the CSS classes will be assigned to them:

* `treeViewCssClass`: The CSS class set on all parts of the tree view,
`table`, `tr` and `td`, always. Default is `tree-view`.
* `selectedTreeNodeCssClass`: The CSS class for the TD of a selected node.
Default is `tree-view-selected-node`.
* `indentationCssClass`: The CSS class for an empty TD that used for indentation
purposes. Default is `tree-view-indentation`.
* `bulletExpandedCssClass`: The CSS class for the TD with a bullet in expanded
node state. Default is `tree-view-bullet-expanded`.
* `bulletCollapsedCssClass`: The CSS class for the TD with a bullet in collapsed
node state. Default is `tree-view-bullet-collapsed`.
* `bulletLeafCssClass`: The CSS class for the TD with a bullet in collapsed
node state. Default is `tree-view-bullet-leaf`.
-}
defaultCssClasses : CssClasses
defaultCssClasses =
    { treeViewCssClass = "tree-view"
    , selectedTreeNodeCssClass = "tree-view-selected-node"
    , indentationCssClass = "tree-view-indentation"
    , bulletExpandedCssClass = "tree-view-bullet-expanded"
    , bulletCollapsedCssClass = "tree-view-bullet-collapsed"
    , bulletLeafCssClass = "tree-view-bullet-leaf"
    }


{-| Configuration for initializing a tree view [`Model`](#Model), to be given to
[`initializeModel`](#initializeModel). Its fields are:
* `uidThunk : Tree.Node d -> NodeUid comparable` gets the uid for a node,
   wrapped in a [NodeUid](#NodeUid) value,
* `labelThunk : Tree.Node d -> String` gets the text representation of a node
for rendering,
* `cssClasses` : the record with the CSS class names to generate the tree view
HTML element with, see [`CssClasses`](#CssClasses) as well as
[`defaultCssClasses`](#defaultCssClasses).
-}
type alias Configuration d comparable =
    { uidThunk : T.Node d -> NodeUid comparable
    , labelThunk : T.Node d -> String
    , cssClasses : CssClasses
    }


{-| Similar to [`Configuration`](#Configuration) but this allows customer rendering of
nodes instead of simple text representation. So instead of `labelThunk` you have

    itemThunk : T.Node d -> Html customMsg

that will turn a node into a bit of HTML, possibly
with its own events. See [`Msg2`](#Msg2).`CustomMsg`, which will carry the custom
messages coming out of the little HTML rendering of a node.
-}
type alias Configuration2 d comparable customMsg =
    { uidThunk : T.Node d -> NodeUid comparable
    , itemThunk : T.Node d -> Html customMsg
    , cssClasses : CssClasses
    }

type Arrow =
    Left
    | Right
    | Up
    | Down
    | Other

type alias Selection comparable =
    { index: Int
    , nodeUid : NodeUid comparable
    }

{- Internals of the model.
-}
type alias Guts d comparable customMsg =
    {
    -- configuration
      uidThunk : T.Node d -> NodeUid comparable
    , labelThunk : T.Node d -> String
    , itemThunk : T.Node d -> Html customMsg
    , cssClasses : CssClasses

    -- data that can be updated
    , forest : List (T.Node d)
    , annotatedNodes : List (T.AnnotatedNode d)
    , collapsedNodeUids : Set.Set comparable
    , visibleAnnotatedNodes : List (T.AnnotatedNode d)
    , selection : Maybe (Selection comparable)
    }

{-| Model for a tree/forest, with the ability to get the uid for a node,
render a node into a string, as well as storing expanded/collapsed presentation
states.

Type variables
* `d` is the custom data,
* `comparable` is the type of the node uid (in practice Int or String)

See [`initializeModel`](#initializeModel).
-}
type Model d comparable customMsg =
    Model (Guts d comparable customMsg)

gutsOf : Model d comparable customMsg -> Guts d comparable customMsg
gutsOf model =
    case model of
        Model guts ->
            guts

{-| Initializes a model for a tree view.
-}
initializeModel : Configuration d comparable -> List (T.Node d) -> Model d comparable Never
initializeModel configuration forest =
    let
        collapedNodeUids = Set.empty
        annotatedNodes = T.listAnnotatedForestNodes forest
    in
        Model
            ( Guts
                  configuration.uidThunk
                  configuration.labelThunk
                  (\_ -> text "")
                  configuration.cssClasses
                  forest
                  annotatedNodes
                  collapedNodeUids
                  (calculateVisibleAnnotatedNodes configuration.uidThunk collapedNodeUids annotatedNodes)
                  Nothing
            )


{-| Just like [`initializeModel`](#initializeModel) only for tree views with
custom rendered nodes.
-}
initializeModel2 : Configuration2 d comparable customMsg -> List (T.Node d) -> Model d comparable customMsg
initializeModel2 configuration forest =
    let
        collapedNodeUids = Set.empty
        annotatedNodes = T.listAnnotatedForestNodes forest
    in
        Model
            ( Guts
                  configuration.uidThunk
                  (\_ -> "")
                  configuration.itemThunk
                  configuration.cssClasses
                  forest
                  annotatedNodes
                  collapedNodeUids
                  (calculateVisibleAnnotatedNodes configuration.uidThunk collapedNodeUids annotatedNodes)
                  Nothing
            )


{-| Message, carrying the uid of the node something happened to.
-}
type Msg comparable
    = Expand (NodeUid comparable)
    | Collapse (NodeUid comparable)
    | Select (NodeUid comparable)
    | ArrowDirection Arrow


{-| The type of messages emitted by tree views with custom rendered nodes.

* Enum `Internal` carries the type of internal [`Msg`](#Msg) messages that
make the tree view work itself. These you feed back to [`update2`](#update2)
just like with any old message,

* Enum `CustomMsg` carries the custom messages emitted by the HTML fragments
that nodes got rendered into. These are the messages that you want to process
yourself. E.g. every node may have a button that can be clicked.
-}
type Msg2 comparable customMsg
    = Internal (Msg comparable)
    | CustomMsg customMsg


modelWithNewExpansionStates : Set.Set comparable -> Model d comparable customMsg -> Model d comparable customMsg
modelWithNewExpansionStates collapsedNodeUids model =
    let
        guts = gutsOf model
        newVisibleAnnotatedNodes =
            calculateVisibleAnnotatedNodes guts.uidThunk collapsedNodeUids guts.annotatedNodes
        selection =
            case guts.selection of
                Nothing ->
                    Nothing
                Just { index, nodeUid } ->
                    case (findAnnotatedNodeIndex guts.uidThunk nodeUid newVisibleAnnotatedNodes) of
                        Nothing ->
                            Nothing
                        Just visibleIndex ->
                            Just <| Selection visibleIndex nodeUid
    in
        Model
            { guts
              | collapsedNodeUids = collapsedNodeUids
              , visibleAnnotatedNodes = newVisibleAnnotatedNodes
              , selection = selection
            }


{-| Updates the model by setting the epxansion state of a node, identified by its
node uid. `True` will expand the node, `False` will collapse it.
-}
updateExpandedStateOf : NodeUid comparable -> Bool -> Model d comparable customMsg -> Model d comparable customMsg
updateExpandedStateOf nodeUid expanded model =
    let
        guts = gutsOf model
        collapsedNodeUids =
            if expanded then
                Set.remove (uidOf nodeUid) guts.collapsedNodeUids
            else
                Set.insert (uidOf nodeUid) guts.collapsedNodeUids
    in
        modelWithNewExpansionStates collapsedNodeUids model


{-| Expands all nodes.
-}
expandAll : Model d comparable customMsg -> Model d comparable customMsg
expandAll model =
    modelWithNewExpansionStates Set.empty model


{-| Collapses all nodes.
-}
collapseAll : Model d comparable customMsg -> Model d comparable customMsg
collapseAll model =
    let
        guts = gutsOf model
        collapsedNodeUids =
            LX.filterNot isLeaf guts.annotatedNodes
                |> List.map (\aN -> guts.uidThunk aN.node)
                |> List.map uidOf
                |> Set.fromList
    in
        modelWithNewExpansionStates collapsedNodeUids model


{-| Updates the data of selected nodes, similar to
[`Tree.updateTreeData`](Tree#updateTreeData). Also updates other bookkeeping
related to the tree view.
-}
updateNodeData : (d -> Bool) -> (d -> d) -> Model d comparable customMsg -> Model d comparable customMsg
updateNodeData selector updater model =
    let
        guts =
            gutsOf model
        forest =
            T.updateForestData selector updater guts.forest
    in
        Model
            { guts
            | forest = forest
            , annotatedNodes = T.listAnnotatedForestNodes forest
            }
            |> modelWithNewExpansionStates guts.collapsedNodeUids


{-| Gets the selected (annotated) node, if any. See [`AnnotatedNode`](Tree#AnnotatedNode).
-}
getSelected : Model d comparable customMsg -> Maybe (T.AnnotatedNode d)
getSelected model =
    let
        guts = gutsOf model
    in
        Maybe.map .index guts.selection
          |> Maybe.andThen (\index -> LX.getAt index guts.visibleAnnotatedNodes)


{-| Gets the currently visible nodes (annotated). See [`AnnotatedNode`](Tree#AnnotatedNode).

Collapsing a non-leaf node will make its children hidden, transitively. The
remaining visible nodes are the ones navigated with the up/down arrow keys.
-}
getVisibleAnnotatedNodes : Model d comparable customMsg -> List (T.AnnotatedNode d)
getVisibleAnnotatedNodes model =
    gutsOf model |> .visibleAnnotatedNodes


stepSelection : Int -> Model d comparable customMsg -> Model d comparable customMsg
stepSelection direction model =
    let
        guts = gutsOf model
        visibleNodesCount = List.length guts.visibleAnnotatedNodes
        newSelectionIndex =
            case guts.selection of
                Nothing ->
                    if direction == 1 then 0 else visibleNodesCount - 1
                Just { index, nodeUid } ->
                    modBy visibleNodesCount (index + direction)
        selectedNodeUidMaybe = LX.getAt newSelectionIndex guts.visibleAnnotatedNodes |> Maybe.map (\aN -> aN.node) |> Maybe.map (\n -> guts.uidThunk n)
    in
        case selectedNodeUidMaybe of
            Nothing ->
                model
            Just nodeUid ->
                Model { guts | selection = Just <| Selection newSelectionIndex nodeUid }


findAnnotatedNodeIndex : (T.Node d -> NodeUid comparable) -> NodeUid comparable -> List (T.AnnotatedNode d) -> Maybe Int
findAnnotatedNodeIndex uidThunk nodeUid annotatedNodes =
    let
        actualNodeUid = uidOf nodeUid
    in
        LX.findIndex (\annotatedNode -> uidOf (uidThunk annotatedNode.node) == actualNodeUid) annotatedNodes


setSelectionTo : NodeUid comparable -> Model d comparable customMsg -> Model d comparable customMsg
setSelectionTo nodeUid model =
    let
        guts = gutsOf model
        visibleIndexMaybe = findAnnotatedNodeIndex guts.uidThunk nodeUid guts.visibleAnnotatedNodes
    in
        case visibleIndexMaybe of
            Nothing ->
                model
            Just visibleIndex ->
                Model { guts | selection = Just <| Selection visibleIndex nodeUid }


{-| Updates the tree view model according to the message.
-}
update : Msg comparable -> Model d comparable customMsg -> Model d comparable customMsg
update message model =
    case message of
        Expand nodeUid ->
            updateExpandedStateOf nodeUid True model
        Collapse nodeUid ->
            updateExpandedStateOf nodeUid False model
        Select nodeUid ->
            setSelectionTo nodeUid model
        ArrowDirection arrow ->
            case arrow of
                Up ->
                    stepSelection -1 model
                Down ->
                    stepSelection 1 model
                Left ->
                    case (gutsOf model |> .selection) of
                        Nothing ->
                            model
                        Just { index, nodeUid } ->
                            updateExpandedStateOf nodeUid False model
                Right ->
                    case (gutsOf model |> .selection) of
                        Nothing ->
                            model
                        Just { index, nodeUid } ->
                            updateExpandedStateOf nodeUid True model
                _ ->
                    model


{-| Just like [`update`](#update) only for tree views with
custom rendered nodes.
-}
update2 : Msg2 comparable customMsg -> Model d comparable customMsg -> Model d comparable customMsg
update2 msg model =
    case msg of
        Internal internalMsg ->
            update internalMsg model

        CustomMsg _ ->
            model


keyDownDecoder : JsonDec.Decoder (Msg comparable)
keyDownDecoder =
    JsonDec.map toArrowDirection (JsonDec.field "key" JsonDec.string)


toArrowDirection : String -> (Msg comparable)
toArrowDirection string =
    case string of
      "ArrowLeft" ->
        ArrowDirection Left

      "ArrowRight" ->
        ArrowDirection Right

      "ArrowUp" ->
        ArrowDirection Up

      "ArrowDown" ->
        ArrowDirection Down

      _ ->
        ArrowDirection Other

{-| Subscriptions, for enabling arrow-key based user interactions, such as:
* selection navigation (up / down arrows),
* collapse & expand action ( left / right arrows).
-}
subscriptions : Model d comparable customMsg -> Sub (Msg comparable)
subscriptions model =
    Events.onKeyDown keyDownDecoder


{-| Just like [`subscriptions`](#subscription) only for tree views with
custom rendered nodes.
-}
subscriptions2 : Model d comparable customMsg -> Sub (Msg2 comparable customMsg)
subscriptions2 model =
    Sub.map Internal <| Events.onKeyDown keyDownDecoder


modelHeight : Model d comparable customMsg -> Int
modelHeight model =
    T.forestHeight (gutsOf model |> .forest)


{-| Render the tree view model into HTML.
-}
view : Model d comparable customMsg  -> Html (Msg comparable)
view model =
    let
        guts = gutsOf model
        height = modelHeight model
    in
        div
            []
            [ table
                [ class guts.cssClasses.treeViewCssClass ]
                (tableRowsForNodes height model)
            ]


{-| Just like [`view`](#view) only for tree views with
custom rendered nodes.
-}
view2 : Model d comparable customMsg -> Html (Msg2 comparable customMsg)
view2 model =
    let
        guts = gutsOf model
        height = modelHeight model
    in
        div
            []
            [ table
                [ class guts.cssClasses.treeViewCssClass ]
                (tableRowsForNodes2 height model)
            ]


tableRowsForNodes : Int -> Model d comparable customMsg -> List (Html (Msg comparable))
tableRowsForNodes height model =
    let
        guts = gutsOf model
    in
        List.map (\annotatedNode -> tableRowForNode height model annotatedNode) guts.visibleAnnotatedNodes


tableRowsForNodes2 : Int -> Model d comparable customMsg -> List (Html (Msg2 comparable customMsg))
tableRowsForNodes2 height model =
    let
        guts = gutsOf model
    in
        List.map (\annotatedNode -> tableRowForNode2 height model annotatedNode) guts.visibleAnnotatedNodes


calculateVisibleAnnotatedNodes : (T.Node d -> NodeUid comparable) -> Set.Set comparable -> List (T.AnnotatedNode d) -> List (T.AnnotatedNode d)
calculateVisibleAnnotatedNodes uidThunk collapsedNodeUids annotatedNodes =
    let
        visibilityFoldThunk : T.AnnotatedNode d -> (Maybe Int, List (T.AnnotatedNode d)) -> (Maybe Int, List (T.AnnotatedNode d))
        visibilityFoldThunk annotatedNode foldState =
            let
                nodeUid = uidThunk annotatedNode.node
                collapsed = Set.member (uidOf nodeUid) collapsedNodeUids
                nodeLevel = annotatedNode.level
            in
                case foldState of
                    (Just visibilityThreshold, annotatedNodesSoFar) ->
                        if visibilityThreshold < nodeLevel then
                            foldState
                        else
                            if collapsed then
                                ( Just nodeLevel, annotatedNodesSoFar ++ [ annotatedNode ] )
                            else
                                ( Nothing, annotatedNodesSoFar ++ [ annotatedNode ] )
                    (Nothing, annotatedNodesSoFar) ->
                        if collapsed then
                            ( Just nodeLevel, annotatedNodesSoFar ++ [ annotatedNode ] )
                        else
                            ( Nothing, annotatedNodesSoFar ++ [ annotatedNode ] )
    in
        List.foldl visibilityFoldThunk (Nothing, []) annotatedNodes |> Tuple.second


type ExpansionState =
    Leaf
    | Expanded
    | Collapsed


isLeaf : T.AnnotatedNode d -> Bool
isLeaf annotatedNode =
    List.isEmpty <| T.childrenOf annotatedNode.node


expansionStateOf : T.AnnotatedNode d -> Model d comparable customMsg -> ExpansionState
expansionStateOf annotatedNode model =
    if (isLeaf annotatedNode) then
        Leaf
    else
        let
            guts = gutsOf model
            nodeUid = guts.uidThunk annotatedNode.node |> uidOf
        in
            if (Set.member nodeUid guts.collapsedNodeUids) then
                Collapsed
            else
                Expanded


bulletTd : ExpansionState -> NodeUid comparable -> CssClasses -> Html (Msg comparable)
bulletTd expansionState nodeUid cssClasses =
    let
        attributes =
            [ classList
                [ (cssClasses.treeViewCssClass, True)
                , (cssClasses.bulletExpandedCssClass, expansionState == Expanded)
                , (cssClasses.bulletCollapsedCssClass, expansionState == Collapsed)
                , (cssClasses.bulletLeafCssClass, expansionState == Leaf)
                ]
            ]
        htmlContent =
            case expansionState of
                Expanded ->
                    label
                      [ onClick (Collapse nodeUid)
                      , class cssClasses.bulletExpandedCssClass
                      ]
                      [ text "O" ]
                Collapsed ->
                    label
                      [ onClick (Expand nodeUid)
                      , class cssClasses.bulletCollapsedCssClass
                      ]
                      [ text "O" ]
                Leaf ->
                    text " "
    in
        td
            attributes
            [ htmlContent ]


nodeTdAttributes : Int -> NodeUid comparable -> Model d comparable customMsg -> List (Attribute msg)
nodeTdAttributes colSpan nodeUid model =
    let
        guts = gutsOf model
        selected =
            guts.selection |> Maybe.map (\s -> s.nodeUid == nodeUid) |> Maybe.withDefault False
    in
        [ classList
            [ (guts.cssClasses.treeViewCssClass, True)
            , (guts.cssClasses.selectedTreeNodeCssClass, selected)
            ]
        , colspan colSpan
        ]


tableRowForNode : Int -> Model d comparable customMsg -> T.AnnotatedNode d -> Html (Msg comparable)
tableRowForNode height model annotatedNode =
    let
        guts = gutsOf model
        level = annotatedNode.level
        indentation = nBlankCells guts.cssClasses level
        bullet = bulletTd expansionState nodeUid guts.cssClasses
        levelsLeft = height - level
        nodeItem = text <| guts.labelThunk annotatedNode.node
        nodeUid = guts.uidThunk <| annotatedNode.node
        expansionState = expansionStateOf annotatedNode model
        renderedNodeTd =
            td
                (nodeTdAttributes levelsLeft nodeUid model)
                [ label
                    [ onClick (Select nodeUid)
                    ]
                    [ nodeItem ]
                ]
    in
        tr
            [ class guts.cssClasses.treeViewCssClass ]
            ( indentation
              ++ [ bullet
                , renderedNodeTd
                ]
            )


tableRowForNode2 : Int -> Model d comparable customMsg -> T.AnnotatedNode d -> Html (Msg2 comparable customMsg)
tableRowForNode2 height model annotatedNode =
    let
        guts = gutsOf model
        level = annotatedNode.level
        indentation = List.map (Html.map Internal) <| nBlankCells guts.cssClasses level
        bullet = Html.map Internal <| bulletTd expansionState nodeUid guts.cssClasses
        levelsLeft = height - level
        nodeItem = Html.map CustomMsg <| guts.itemThunk annotatedNode.node
        nodeUid = guts.uidThunk <| annotatedNode.node
        expansionState = expansionStateOf annotatedNode model
        renderedNodeTd =
            td
                (nodeTdAttributes levelsLeft nodeUid model)
                [ label
                    [ onClick <| Internal (Select nodeUid)
                    ]
                    [ nodeItem ]
                ]
    in
        tr
            [ class guts.cssClasses.treeViewCssClass ]
            ( indentation
              ++ [ bullet
                , renderedNodeTd
                ]
            )


nBlankCells : CssClasses -> Int -> List (Html (Msg comparable))
nBlankCells cssClasses currentDepth =
    List.repeat
        currentDepth
          ( td
            [ classList
                [ (cssClasses.treeViewCssClass, True)
                , (cssClasses.indentationCssClass, True)
                ]
            ]
            [ text " " ]
          )
